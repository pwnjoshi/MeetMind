import Foundation
import AVFoundation
import CryptoKit

/// How much of the final transcript came from windows transcribed during
/// recording. Contains no transcript text, only durations.
public struct TranscriptReuseSummary: Sendable, Equatable {
    public let totalSeconds: Double
    public let reusedSeconds: Double
    public let transcribedSeconds: Double

    public init(totalSeconds: Double, reusedSeconds: Double, transcribedSeconds: Double) {
        self.totalSeconds = totalSeconds
        self.reusedSeconds = reusedSeconds
        self.transcribedSeconds = transcribedSeconds
    }

    /// Every second of audio already had a transcript from recording time.
    public var fullyReused: Bool { reusedSeconds > 0 && transcribedSeconds <= 0.001 }
    public var partiallyReused: Bool { reusedSeconds > 0 && transcribedSeconds > 0.001 }
}

/// Process-local, thread-safe record of transcript reuse so the processing
/// screen can describe what actually happened without owning the pipeline.
public final class TranscriptReuseRegistry: @unchecked Sendable {
    public static let shared = TranscriptReuseRegistry()
    private let lock = NSLock()
    private var storage: [UUID: TranscriptReuseSummary] = [:]

    public init() {}

    public func summary(for meetingID: UUID) -> TranscriptReuseSummary? {
        lock.lock(); defer { lock.unlock() }
        return storage[meetingID]
    }

    func record(_ summary: TranscriptReuseSummary, for meetingID: UUID) {
        lock.lock(); defer { lock.unlock() }
        storage[meetingID] = summary
    }

    func clear(meetingID: UUID) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: meetingID)
    }
}

struct TimeGap: Equatable, Sendable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

struct PreparedTranscriptPlan {
    /// Turns from prepared windows that lie outside every gap.
    let turns: [AnalysisTurn]
    /// Time ranges that still need transcription. Empty means fully covered.
    let gaps: [TimeGap]
    let reusedSeconds: Double
}

/// A final-pass analysis result computed while recording, keyed by a hash of the
/// chunk's turn IDs and texts. Speaker labels are deliberately not part of the key.
struct PreAnalysisEntry: Codable, Sendable {
    let key: String
    let result: LocalAnalysisResult
}

struct PreAnalysisStore: Codable, Sendable {
    /// Hash of everything besides the chunk that influences the model output
    /// (prompt version, model revision, context sizes, meeting day).
    var contextKey: String
    var entries: [PreAnalysisEntry]
    /// Byte-planned chunk count at the last complete check. A larger count means
    /// another chunk has closed since, which is the trigger for new work.
    var checkedChunkCount: Int
}

enum RecordingReuse {
    /// Prepared windows are contiguous to within this much.
    static let toleranceSeconds = 0.75
    /// Uncovered ranges at or below this length are not worth a Whisper load.
    static let minimumGapSeconds = 1.0
    /// Each gap costs a model load, so nearby gaps are bridged beyond this.
    static let maximumGapCount = 3
    /// Above this uncovered fraction one pass over the whole file is cheaper.
    static let wholeFileFraction = 0.7

    static func plan(windows: [PreparedRecordingChunk], duration: Double) -> PreparedTranscriptPlan {
        guard duration > 0 else { return PreparedTranscriptPlan(turns: [], gaps: [], reusedSeconds: 0) }
        if windows.isEmpty {
            return PreparedTranscriptPlan(turns: [], gaps: [TimeGap(start: 0, end: duration)], reusedSeconds: 0)
        }
        let intervals = windows
            .map { (start: max(0, $0.contentStartTime), end: min(duration, $0.endTime)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [(start: Double, end: Double)] = []
        for interval in intervals {
            if var last = merged.last, interval.start <= last.end + toleranceSeconds {
                last.end = max(last.end, interval.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(interval)
            }
        }
        var gaps: [TimeGap] = []
        var cursor = 0.0
        for interval in merged {
            if interval.start - cursor > minimumGapSeconds { gaps.append(TimeGap(start: cursor, end: interval.start)) }
            cursor = max(cursor, interval.end)
        }
        if duration - cursor > minimumGapSeconds { gaps.append(TimeGap(start: cursor, end: duration)) }

        // Bridge the two gaps separated by the shortest already-covered island.
        while gaps.count > maximumGapCount {
            var bestIndex = 0
            var bestSpan = Double.infinity
            for index in 0..<(gaps.count - 1) {
                let span = gaps[index + 1].start - gaps[index].end
                if span < bestSpan { bestSpan = span; bestIndex = index }
            }
            gaps[bestIndex] = TimeGap(start: gaps[bestIndex].start, end: gaps[bestIndex + 1].end)
            gaps.remove(at: bestIndex + 1)
        }
        var gapTotal = gaps.reduce(0.0) { $0 + $1.duration }
        if gapTotal / duration > wholeFileFraction {
            gaps = [TimeGap(start: 0, end: duration)]
            gapTotal = duration
        }
        let wholeFile = gaps.count == 1 && gaps[0].start <= 0 && gaps[0].end >= duration
        var kept: [AnalysisTurn] = []
        if !wholeFile {
            var seen = Set<String>()
            let ordered = windows.sorted { $0.sequence < $1.sequence }.flatMap(\.turns).sorted { $0.start < $1.start }
            kept = ordered.filter { turn in
                let middle = (turn.start + turn.end) / 2
                guard !gaps.contains(where: { middle >= $0.start && middle < $0.end }) else { return false }
                return seen.insert("\(Int(turn.start * 10))|\(turn.text.lowercased())").inserted
            }
        }
        return PreparedTranscriptPlan(turns: kept, gaps: gaps, reusedSeconds: max(0, duration - gapTotal))
    }

    /// Turns from the windows that form unbroken coverage starting at time zero.
    /// Chunk planning is prefix-stable, so analyses of closed chunks computed on
    /// this prefix match the final pass.
    static func contiguousPrefixTurns(_ windows: [PreparedRecordingChunk]) -> [AnalysisTurn] {
        let ordered = windows.sorted { $0.sequence < $1.sequence }
        guard let first = ordered.first, first.contentStartTime <= toleranceSeconds else { return [] }
        var coveredEnd = first.contentStartTime
        var included: [PreparedRecordingChunk] = []
        for window in ordered {
            guard window.contentStartTime <= coveredEnd + minimumGapSeconds else { break }
            included.append(window)
            coveredEnd = max(coveredEnd, window.endTime)
        }
        var seen = Set<String>()
        return included.flatMap(\.turns).sorted { $0.start < $1.start }.filter { turn in
            seen.insert("\(Int(turn.start * 10))|\(turn.text.lowercased())").inserted
        }
    }

    /// Moves clip-relative timestamps onto the meeting timeline and keeps only
    /// turns that belong to the gap (the adjacent prepared window owns the rest).
    static func offsetGapTurns(_ raw: [AnalysisTurn], gap: TimeGap, index: Int) -> [AnalysisTurn] {
        var result: [AnalysisTurn] = []
        for (turnIndex, turn) in raw.enumerated() {
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let start = turn.start + gap.start
            let end = turn.end + gap.start
            let middle = (start + end) / 2
            guard middle >= gap.start, middle <= gap.end else { continue }
            result.append(AnalysisTurn(id: "gap-\(index)-\(turnIndex)", text: turn.text,
                                       start: start, end: end, speaker: nil))
        }
        return result
    }

    /// Copies `[start, end)` of `source` into a temporary file by reading PCM.
    /// The caller removes the returned file's directory with `removeClip`.
    static func extractAudio(from source: URL, start: Double, end: Double) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        guard format.sampleRate > 0 else { throw OfflineError.unavailable("Recording audio format is unreadable.") }
        let first = AVAudioFramePosition(max(0, start) * format.sampleRate)
        let last = min(input.length, AVAudioFramePosition(end * format.sampleRate))
        guard last > first else { throw OfflineError.unavailable("Recording range is empty.") }
        input.framePosition = first
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManentGap-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("gap.caf")
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let capacity: AVAudioFrameCount = 16_384
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw OfflineError.unavailable("Unable to allocate audio for the unprepared range.")
            }
            var remaining = last - first
            while remaining > 0 {
                try Task.checkCancellation()
                let count = AVAudioFrameCount(min(AVAudioFramePosition(capacity), remaining))
                try input.read(into: buffer, frameCount: count)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return url
    }

    static func removeClip(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Hash of the chunk's turn IDs and texts. Speaker labels are excluded because
    /// they are unknown while recording. IDs are included because evidence
    /// references them.
    static func chunkKey(_ turns: [AnalysisTurn]) -> String {
        var hasher = SHA256()
        for turn in turns {
            hasher.update(data: Data(turn.id.utf8))
            hasher.update(data: Data([0x1F]))
            hasher.update(data: Data(turn.text.utf8))
            hasher.update(data: Data([0x1E]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func contextKey(profile: ModelProfile, configuration: LocalModelConfiguration,
                           chunkBytes: Int, meetingDate: Date, timezone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? TimeZone.current
        let day = calendar.dateComponents([.year, .month, .day], from: meetingDate)
        return [OfflineAnalysisContract.promptVersion, "\(profile.id):\(profile.revision)",
                "ctx\(configuration.contextTokens)", "in\(configuration.inputTokens)", "bytes\(chunkBytes)",
                "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)", timezone].joined(separator: "|")
    }
}
