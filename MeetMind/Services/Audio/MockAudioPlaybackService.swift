import Foundation

public final class MockAudioPlaybackService: AudioPlaybackServiceProtocol, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    
    private var internalState: PlaybackState = .idle
    public var state: PlaybackState {
        get {
            lock.lock()
            defer { lock.unlock() }
            return internalState
        }
        set {
            lock.lock()
            internalState = newValue
            lock.unlock()
        }
    }
    
    private var internalCurrentTime: TimeInterval = 0.0
    public var currentTime: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return internalCurrentTime
        }
        set {
            lock.lock()
            internalCurrentTime = newValue
            lock.unlock()
        }
    }
    
    private var internalDuration: TimeInterval = 180.0
    public var duration: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return internalDuration
        }
        set {
            lock.lock()
            internalDuration = newValue
            lock.unlock()
        }
    }
    
    private var internalPlaybackRate: Float = 1.0
    public var playbackRate: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return internalPlaybackRate
        }
        set {
            lock.lock()
            let validRate = newValue.isFinite ? newValue : 1.0
            internalPlaybackRate = max(0.5, min(2.0, validRate))
            lock.unlock()
        }
    }
    public var shouldThrowError: AudioPlaybackError? = nil
    public var observers: [UUID: @Sendable (TimeInterval) -> Void] = [:]
    
    private var playbackTask: Task<Void, Never>?
    
    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return internalState == .playing
    }
    
    public init(duration: TimeInterval = 180.0) {
        self.internalDuration = duration
    }
    
    deinit {
        stopPlaybackSimulation()
    }
    
    public func loadAudio(url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if let error = shouldThrowError { throw error }
        internalState = .idle
        internalCurrentTime = 0.0
    }
    
    public func play() throws {
        lock.lock()
        if let error = shouldThrowError {
            lock.unlock()
            throw error
        }
        internalState = .playing
        lock.unlock()
        
        startPlaybackSimulation()
    }
    
    public func pause() {
        lock.lock()
        internalState = .paused
        lock.unlock()
        stopPlaybackSimulation()
    }
    
    public func stop() {
        lock.lock()
        internalState = .stopped
        internalCurrentTime = 0.0
        lock.unlock()
        stopPlaybackSimulation()
        notifyObservers(time: 0.0)
    }
    
    public func seek(to time: TimeInterval) {
        lock.lock()
        let clamped = max(0.0, min(time, internalDuration))
        internalCurrentTime = clamped
        lock.unlock()
        notifyObservers(time: clamped)
    }
    
    public func addTimeObserver(interval: TimeInterval, handler: @Sendable @escaping (TimeInterval) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = handler
        lock.unlock()
        return id
    }
    
    public func removeTimeObserver(id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }
    
    private func startPlaybackSimulation() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { break }
                guard let self = self else { return }
                self.lock.lock()
                let isPlaying = self.internalState == .playing
                let rate = self.internalPlaybackRate
                let totalDuration = self.internalDuration
                if isPlaying {
                    self.internalCurrentTime += Double(rate) * 0.1
                    if self.internalCurrentTime >= totalDuration {
                        self.internalCurrentTime = totalDuration
                        self.internalState = .completed
                    }
                }
                let curTime = self.internalCurrentTime
                let state = self.internalState
                let handlers = Array(self.observers.values)
                self.lock.unlock()
                
                for handler in handlers {
                    handler(curTime)
                }
                
                if state == .completed {
                    break
                }
            }
        }
    }
    
    private func stopPlaybackSimulation() {
        playbackTask?.cancel()
        playbackTask = nil
    }
    
    private func notifyObservers(time: TimeInterval) {
        lock.lock()
        let handlers = Array(observers.values)
        lock.unlock()
        for handler in handlers {
            handler(time)
        }
    }
}
