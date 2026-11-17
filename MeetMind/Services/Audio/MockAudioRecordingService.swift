import Foundation

public final class MockAudioRecordingService: AudioRecordingServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    public var state: RecordingState = .idle
    public var currentDuration: TimeInterval = 0.0
    public var simulatedPowerLevels: [Float] = [0.15, 0.35, 0.65, 0.85, 0.50, 0.30, 0.10, 0.45, 0.75, 0.90]
    public var shouldThrowError: AudioRecordingError? = nil
    public var destinationURL: URL?
    public var isCancelled: Bool = false
    public var wasRecordingCancelled: Bool { isCancelled }
    public var simulateFileAlreadyDeleted: Bool = false
    
    private var meterContinuation: AsyncStream<Float>.Continuation?
    private var simulationTask: Task<Void, Never>?
    
    public var audioMeterStream: AsyncStream<Float> {
        AsyncStream { continuation in
            self.lock.lock()
            self.meterContinuation = continuation
            self.lock.unlock()
            
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.meterContinuation = nil
                self?.lock.unlock()
            }
        }
    }
    
    public init() {}
    
    public func startRecording(destinationURL: URL) async throws {
        lock.lock()
        if let error = shouldThrowError {
            lock.unlock()
            throw error
        }
        self.destinationURL = destinationURL
        self.state = .recording
        self.currentDuration = 0.0
        self.isCancelled = false
        lock.unlock()
        
        startSimulation()
    }
    
    public func pauseRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = shouldThrowError { throw error }
        state = .paused
        meterContinuation?.yield(0.0)
    }
    
    public func resumeRecording() throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = shouldThrowError { throw error }
        state = .recording
    }
    
    public func stopRecording() async throws -> URL {
        lock.lock()
        if let error = shouldThrowError {
            lock.unlock()
            throw error
        }
        state = .stopped
        let url = destinationURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mock_recording.m4a")
        lock.unlock()
        
        stopSimulation()
        meterContinuation?.yield(0.0)
        meterContinuation?.finish()
        return url
    }
    
    public func cancelRecording() throws {
        lock.lock()
        if let error = shouldThrowError { lock.unlock(); throw error }
        state = .idle
        isCancelled = true
        currentDuration = 0.0
        let continuation = meterContinuation
        lock.unlock()
        stopSimulation()
        continuation?.yield(0.0)
        continuation?.finish()
    }
    
    private func startSimulation() {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self = self else { return }
                self.lock.lock()
                let isRecording = self.state == .recording
                let levels = self.simulatedPowerLevels
                if isRecording {
                    self.currentDuration += 0.1
                }
                let continuation = self.meterContinuation
                self.lock.unlock()
                
                if isRecording && !levels.isEmpty {
                    let level = levels[index % levels.count]
                    continuation?.yield(level)
                    index += 1
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
    }
}
