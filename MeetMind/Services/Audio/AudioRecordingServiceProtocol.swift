import Foundation
import AVFoundation

/// Lifecycle states of the audio recording engine
public enum RecordingState: String, Codable, Sendable, Equatable {
    case idle
    case preparing
    case recording
    case paused
    case stopped
}

/// Errors thrown by the audio recording service
public enum AudioRecordingError: LocalizedError, Sendable, Equatable {
    case permissionDenied
    case audioSessionSetupFailed(String)
    case engineStartFailed(String)
    case inputNodeUnavailable
    case fileCreationFailed(String)
    case invalidState(String)
    case recordingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied by the user."
        case .audioSessionSetupFailed(let reason):
            return "Failed to configure audio session: \(reason)"
        case .engineStartFailed(let reason):
            return "AVAudioEngine failed to start: \(reason)"
        case .inputNodeUnavailable:
            return "Audio input node is not available on this device."
        case .fileCreationFailed(let reason):
            return "Could not create destination audio file: \(reason)"
        case .invalidState(let reason):
            return "Invalid recording state operation: \(reason)"
        case .recordingFailed(let reason):
            return "Recording session encountered an error: \(reason)"
        }
    }
}

/// Protocol defining the contract for meeting audio capture
public protocol AudioRecordingServiceProtocol: AnyObject, Sendable {
    /// Current state of the recorder
    var state: RecordingState { get }
    
    /// Total duration of active recorded audio (excluding paused time)
    var currentDuration: TimeInterval { get }
    
    /// Real-time 60Hz stream of normalized linear audio power levels (0.0 to 1.0)
    var audioMeterStream: AsyncStream<Float> { get }
    
    /// Starts recording and writing audio to the specified destination URL
    func startRecording(destinationURL: URL) async throws
    
    /// Pauses the active recording session without finalizing the file
    func pauseRecording() throws
    
    /// Resumes a paused recording session
    func resumeRecording() throws
    
    /// Stops recording, flushes buffers, closes audio file, and returns the final file URL
    func stopRecording() async throws -> URL
    
    /// Cancels recording and deletes the partially recorded audio file
    func cancelRecording() throws
}
