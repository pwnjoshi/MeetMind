import Foundation
import AVFoundation

public final class AudioPlaybackService: NSObject, AudioPlaybackServiceProtocol, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var internalState: PlaybackState = .idle
    private var player: AVAudioPlayer?
    private var currentRate: Float = 1.0
    private var observers: [UUID: @Sendable (TimeInterval) -> Void] = [:]
    private var pollingTask: Task<Void, Never>?
    
    public var state: PlaybackState {
        lock.lock()
        defer { lock.unlock() }
        return internalState
    }
    
    public var currentTime: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return player?.currentTime ?? 0.0
    }
    
    public var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return player?.duration ?? 0.0
    }
    
    public var playbackRate: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentRate
        }
        set {
            lock.lock()
            let validRate = newValue.isFinite ? newValue : 1.0
            let clamped = max(0.5, min(2.0, validRate))
            currentRate = clamped
            player?.rate = clamped
            lock.unlock()
        }
    }
    
    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return internalState == .playing
    }
    
    public override init() {
        super.init()
    }
    
    deinit {
        stopPolling()
        player?.stop()
    }
    
    public func loadAudio(url: URL) throws {
        lock.lock()
        internalState = .loading
        lock.unlock()
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            lock.lock()
            internalState = .idle
            lock.unlock()
            throw AudioPlaybackError.fileNotFound(url)
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
            audioPlayer.enableRate = true
            audioPlayer.rate = currentRate
            audioPlayer.prepareToPlay()
            
            lock.lock()
            self.player = audioPlayer
            self.internalState = .idle
            lock.unlock()
        } catch {
            lock.lock()
            self.internalState = .idle
            lock.unlock()
            throw AudioPlaybackError.playerInitializationFailed(error.localizedDescription)
        }
    }
    
    public func play() throws {
        lock.lock()
        guard let player = player else {
            lock.unlock()
            throw AudioPlaybackError.invalidState("Audio player has not been loaded.")
        }
        player.rate = currentRate
        let success = player.play()
        if success {
            internalState = .playing
            lock.unlock()
            startPolling()
        } else {
            internalState = .idle
            lock.unlock()
            throw AudioPlaybackError.invalidState("Audio player failed to begin playback.")
        }
    }
    
    public func pause() {
        lock.lock()
        player?.pause()
        internalState = .paused
        lock.unlock()
        stopPolling()
    }
    
    public func stop() {
        lock.lock()
        player?.stop()
        player?.currentTime = 0.0
        internalState = .stopped
        lock.unlock()
        stopPolling()
        notifyObservers(time: 0.0)
    }
    
    public func seek(to time: TimeInterval) {
        lock.lock()
        guard let player = player else {
            lock.unlock()
            return
        }
        let clampedTime = max(0.0, min(time, player.duration))
        player.currentTime = clampedTime
        lock.unlock()
        notifyObservers(time: clampedTime)
    }
    
    public func addTimeObserver(interval: TimeInterval, handler: @Sendable @escaping (TimeInterval) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = handler
        let shouldStart = internalState == .playing && pollingTask == nil
        lock.unlock()
        
        if shouldStart {
            startPolling()
        }
        return id
    }
    
    public func removeTimeObserver(id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        let isEmpty = observers.isEmpty
        lock.unlock()
        
        if isEmpty {
            stopPolling()
        }
    }
    
    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.lock.lock()
                let isStillPlaying = self.internalState == .playing
                let curTime = self.player?.currentTime ?? 0.0
                let handlers = Array(self.observers.values)
                self.lock.unlock()
                
                if isStillPlaying {
                    for handler in handlers {
                        handler(curTime)
                    }
                } else {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms interval (20Hz UI update)
            }
        }
    }
    
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    private func notifyObservers(time: TimeInterval) {
        lock.lock()
        let handlers = Array(observers.values)
        lock.unlock()
        for handler in handlers {
            handler(time)
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        internalState = .completed
        let totalDuration = self.player?.duration ?? 0.0
        lock.unlock()
        stopPolling()
        notifyObservers(time: totalDuration)
    }
}
