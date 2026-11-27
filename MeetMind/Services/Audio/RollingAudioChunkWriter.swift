import AVFoundation
import Foundation

/// A durable piece of a recording that has been sealed while recording is still
/// in progress. `startTime` includes the overlap used to avoid cutting a word
/// at the edge of a chunk; `contentStartTime` is the unique timeline position.
public struct RecordingAudioChunk: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sequence: Int
    public let filePath: String
    public let startTime: TimeInterval
    public let contentStartTime: TimeInterval
    public let endTime: TimeInterval

    public var fileURL: URL { URL(fileURLWithPath: filePath) }
}

private struct RecordingAudioChunkManifest: Codable {
    var version = 1
    var chunks: [RecordingAudioChunk]
}

/// Writes 30-second CAF files while the main M4A is recorded. The files are
/// intentionally kept in the app container: they let the analysis pipeline
/// make durable progress before Stop and recover safely after an interruption.
/// The 5-second overlap is stitched out by timestamps during finalization.
public final class RollingAudioChunkWriter: @unchecked Sendable {
    public static let chunkDuration: TimeInterval = 30
    public static let overlapDuration: TimeInterval = 5

    private let lock = NSLock()
    private let directory: URL
    private let manifestURL: URL
    private var chunks: [RecordingAudioChunk] = []
    private var activeFile: AVAudioFile?
    private var activeURL: URL?
    private var activeContentStart: TimeInterval = 0
    private var activeWrittenDuration: TimeInterval = 0
    private var activeOverlapDuration: TimeInterval = 0
    private var elapsedContentDuration: TimeInterval = 0
    private var overlapBuffers: [AVAudioPCMBuffer] = []
    private var overlapDuration: TimeInterval = 0
    private var lastError: Error?

    public init(meetingID: UUID, fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
        directory = documents.appendingPathComponent("RecordingChunks", isDirectory: true)
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")
        // A meeting may be re-recorded. Never let an abandoned manifest from a
        // prior attempt be mistaken for work belonging to this recording.
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(resourceValues)
    }

    /// Call from one audio-stream consumer. Returns the chunk that was just
    /// sealed, if any, so callers may enqueue it for low-priority inference.
    @discardableResult
    public func append(_ buffer: AVAudioPCMBuffer) throws -> RecordingAudioChunk? {
        lock.lock()
        defer { lock.unlock() }
        if let lastError { throw lastError }
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return nil }
        do {
            if activeFile == nil { try beginChunk(using: buffer) }
            try activeFile?.write(from: buffer)
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            activeWrittenDuration += duration
            elapsedContentDuration += duration
            retainOverlap(copy(of: buffer), duration: duration)
            if activeContentDuration >= Self.chunkDuration {
                let completed = try sealActiveChunk()
                try beginChunk(using: buffer)
                return completed
            }
            return nil
        } catch {
            lastError = error
            throw error
        }
    }

    /// Seals the partial final chunk. It is safe to call more than once.
    public func finish() throws -> [RecordingAudioChunk] {
        lock.lock()
        defer { lock.unlock() }
        if let lastError { throw lastError }
        if activeFile != nil, activeContentDuration > 0 { _ = try sealActiveChunk() }
        return chunks
    }

    public func discard() {
        lock.lock()
        activeFile = nil
        activeURL = nil
        chunks.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: directory)
    }

    private var activeContentDuration: TimeInterval {
        // The first five seconds in every later file are overlap, not new time.
        max(0, activeWrittenDuration - activeOverlapDuration)
    }

    private func beginChunk(using buffer: AVAudioPCMBuffer) throws {
        let sequence = chunks.count
        let url = directory.appendingPathComponent(String(format: "chunk-%04d.caf", sequence))
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                   commonFormat: buffer.format.commonFormat,
                                   interleaved: buffer.format.isInterleaved)
        activeFile = file
        activeURL = url
        activeContentStart = elapsedContentDuration
        activeWrittenDuration = 0
        activeOverlapDuration = 0
        // A new chunk starts with the tail of the preceding chunk. Write it
        // before new microphone buffers so the file can stand on its own.
        for overlap in overlapBuffers {
            try file.write(from: overlap)
            let duration = Double(overlap.frameLength) / overlap.format.sampleRate
            activeWrittenDuration += duration
            activeOverlapDuration += duration
        }
    }

    private func sealActiveChunk() throws -> RecordingAudioChunk {
        guard let url = activeURL else { throw AudioRecordingError.recordingFailed("Chunk output was unavailable.") }
        let chunk = RecordingAudioChunk(id: UUID(), sequence: chunks.count, filePath: url.path,
                                        startTime: max(0, activeContentStart - min(Self.overlapDuration, activeContentStart)),
                                        contentStartTime: activeContentStart,
                                        endTime: elapsedContentDuration)
        activeFile = nil
        activeURL = nil
        activeWrittenDuration = 0
        activeOverlapDuration = 0
        chunks.append(chunk)
        try persistManifest()
        return chunk
    }

    private func retainOverlap(_ buffer: AVAudioPCMBuffer?, duration: TimeInterval) {
        guard let buffer else { return }
        overlapBuffers.append(buffer)
        overlapDuration += duration
        while overlapDuration > Self.overlapDuration, let first = overlapBuffers.first {
            overlapBuffers.removeFirst()
            overlapDuration -= Double(first.frameLength) / first.format.sampleRate
        }
    }

    private func copy(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<source.count where source[index].mData != nil && destination[index].mData != nil {
            memcpy(destination[index].mData!, source[index].mData!, Int(source[index].mDataByteSize))
        }
        return copy
    }

    private func persistManifest() throws {
        let data = try JSONEncoder().encode(RecordingAudioChunkManifest(chunks: chunks))
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
