import Foundation

/// Lifecycle states of the audio playback engine
public enum PlaybackState: String, Codable, Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case completed
}

/// Errors thrown by the audio playback service
public enum AudioPlaybackError: LocalizedError, Sendable, Equatable {
    case fileNotFound(URL)
    case playerInitializationFailed(String)
    case invalidState(String)
    case seekFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Audio file not found at path: \(url.path)"
        case .playerInitializationFailed(let reason):
            return "Failed to initialize AVAudioPlayer: \(reason)"
        case .invalidState(let reason):
            return "Invalid playback state operation: \(reason)"
        case .seekFailed(let reason):
            return "Seek operation failed: \(reason)"
        }
    }
}

/// Protocol defining the contract for meeting audio playback and scrubbing
public protocol AudioPlaybackServiceProtocol: AnyObject, Sendable {
    /// Current playback state
    var state: PlaybackState { get }
    
    /// Current playback playhead position in seconds
    var currentTime: TimeInterval { get }
    
    /// Total duration of the loaded audio file in seconds
    var duration: TimeInterval { get }
    
    /// Variable playback rate (0.75x, 1.0x, 1.25x, 1.5x, 2.0x)
    var playbackRate: Float { get set }
    
    /// Whether audio is actively playing
    var isPlaying: Bool { get }
    
    /// Loads an audio file from the specified URL and prepares the player
    func loadAudio(url: URL) throws
    
    /// Starts or resumes audio playback
    func play() throws
    
    /// Pauses active playback
    func pause()
    
    /// Stops playback and resets playhead to start
    func stop()
    
    /// Seeks directly to the specified time offset in seconds
    func seek(to time: TimeInterval)
    
    /// Registers a periodic time observer invoked at the requested interval
    func addTimeObserver(interval: TimeInterval, handler: @Sendable @escaping (TimeInterval) -> Void) -> UUID
    
    /// Removes a previously registered time observer
    func removeTimeObserver(id: UUID)
}
