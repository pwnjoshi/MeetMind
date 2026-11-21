import AVFoundation
import Foundation

public final class MockAudioRecordingService: AudioRecordingServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var state: RecordingState = .idle
    public var currentDuration: TimeInterval = 0.0
    public var simulatedPowerLevels: [Float] = [0.15, 0.35, 0.65, 0.85, 0.50, 0.30, 0.10, 0.45, 0.75, 0.90]
    public var shouldThrowError: AudioRecordingError?
    public var startError: AudioRecordingError?
    public var pauseError: AudioRecordingError?
    public var resumeError: AudioRecordingError?
    public var stopError: AudioRecordingError?
    public var cancelError: AudioRecordingError?
    public var destinationURL: URL?
    public var isCancelled = false
    public var wasRecordingCancelled: Bool { isCancelled }
    public var simulateFileAlreadyDeleted = false
    public var automaticallyAdvancesDuration = true
    public var createsCanonicalFileOnStop = true
    public var canonicalFrameCount: AVAudioFrameCount = 4_410

    private var meterContinuation: AsyncStream<Float>.Continuation?
    private var bufferContinuations: [UUID: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]
    private var interruptionContinuations: [UUID: AsyncStream<RecordingInterruptionEvent>.Continuation] = [:]
    private var simulationTask: Task<Void, Never>?

    public var audioMeterStream: AsyncStream<Float> {
        AsyncStream { continuation in
            lock.lock()
            meterContinuation = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.meterContinuation = nil
                self?.lock.unlock()
            }
        }
    }

    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let id = UUID()
            lock.lock()
            bufferContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.bufferContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public var interruptionStream: AsyncStream<RecordingInterruptionEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation in
            let id = UUID()
            lock.lock()
            interruptionContinuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.interruptionContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public init() {}

    public func startRecording(destinationURL: URL) async throws {
        lock.lock()
        if let error = startError ?? shouldThrowError {
            lock.unlock()
            throw error
        }
        self.destinationURL = destinationURL
        state = .recording
        currentDuration = 0
        isCancelled = false
        lock.unlock()
        startSimulation()
    }

    public func pauseRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = pauseError ?? shouldThrowError { throw error }
        state = .paused
        meterContinuation?.yield(0)
    }

    public func resumeRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = resumeError ?? shouldThrowError { throw error }
        state = .recording
    }

    public func stopRecording() async throws -> URL {
        lock.lock()
        if let error = stopError ?? shouldThrowError {
            lock.unlock()
            throw error
        }
        state = .stopped
        let url = destinationURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("mock_recording.m4a")
        lock.unlock()

        stopSimulation()
        if createsCanonicalFileOnStop && !simulateFileAlreadyDeleted {
            try writeCanonicalAudio(to: url)
        }
        meterContinuation?.yield(0)
        meterContinuation?.finish()
        finishBufferStreams()
        finishInterruptionStreams()
        return url
    }

    public func cancelRecording() throws {
        lock.lock()
        if let error = cancelError ?? shouldThrowError {
            lock.unlock()
            throw error
        }
        state = .idle
        isCancelled = true
        currentDuration = 0
        let continuation = meterContinuation
        lock.unlock()
        stopSimulation()
        continuation?.yield(0)
        continuation?.finish()
        finishBufferStreams()
        finishInterruptionStreams()
        if !simulateFileAlreadyDeleted, let destinationURL {
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }

    public func emitAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let continuations = Array(bufferContinuations.values)
        lock.unlock()
        continuations.forEach { $0.yield(buffer) }
    }

    public func simulateInterruption(
        code: RecordingInterruptionCode = .audioSession,
        canResume: Bool = true,
        hasEnded: Bool = true
    ) {
        lock.lock()
        state = .interrupted
        let continuations = Array(interruptionContinuations.values)
        lock.unlock()
        let event = RecordingInterruptionEvent(code: code, canResume: canResume, hasEnded: hasEnded)
        continuations.forEach { $0.yield(event) }
    }

    private func writeCanonicalAudio(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: canonicalFrameCount) else {
            throw AudioRecordingError.fileCreationFailed("The mock audio format could not be created.")
        }
        buffer.frameLength = canonicalFrameCount
        if let channel = buffer.floatChannelData?.pointee {
            channel.initialize(repeating: 0, count: Int(canonicalFrameCount))
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
    }

    private func startSimulation() {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.lock.lock()
                let isRecording = self.state == .recording
                let levels = self.simulatedPowerLevels
                if isRecording && self.automaticallyAdvancesDuration { self.currentDuration += 0.1 }
                let continuation = self.meterContinuation
                self.lock.unlock()
                if isRecording && !levels.isEmpty {
                    continuation?.yield(levels[index % levels.count])
                    index += 1
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
    }

    private func finishBufferStreams() {
        lock.lock()
        let continuations = Array(bufferContinuations.values)
        bufferContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }

    private func finishInterruptionStreams() {
        lock.lock()
        let continuations = Array(interruptionContinuations.values)
        interruptionContinuations.removeAll()
        lock.unlock()
        continuations.forEach { $0.finish() }
    }
}
