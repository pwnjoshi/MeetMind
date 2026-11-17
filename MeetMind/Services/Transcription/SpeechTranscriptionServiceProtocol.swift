import Foundation
import Speech
import AVFoundation

/// Individual recognized word or phrase segment with precise time alignment
public struct LiveTranscriptSegment: Sendable, Equatable, Codable {
    public let text: String
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let confidence: Float
    
    public init(text: String, startTime: TimeInterval, duration: TimeInterval, confidence: Float = 1.0) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.confidence = confidence
    }
    
    public var endTime: TimeInterval {
        startTime + duration
    }
}

/// Streaming chunk yielded during live speech recognition
public struct LiveTranscriptChunk: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let segments: [LiveTranscriptSegment]
    
    public init(text: String, isFinal: Bool, segments: [LiveTranscriptSegment] = []) {
        self.text = text
        self.isFinal = isFinal
        self.segments = segments
    }
}

/// Errors thrown by the speech transcription service
public enum SpeechTranscriptionError: LocalizedError, Sendable, Equatable {
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case recognitionRequestFailed(String)
    case audioFileReadFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition authorization was denied."
        case .recognizerUnavailable:
            return "SFSpeechRecognizer is unavailable on this device or locale."
        case .onDeviceRecognitionUnavailable:
            return "On-device speech recognition is not supported on this device."
        case .recognitionRequestFailed(let reason):
            return "Speech recognition request failed: \(reason)"
        case .audioFileReadFailed(let reason):
            return "Failed to read audio file for transcription: \(reason)"
        }
    }
}

/// Protocol defining speech transcription capabilities
public protocol SpeechTranscriptionServiceProtocol: AnyObject, Sendable {
    /// Whether the speech recognizer is currently available
    var isAvailable: Bool { get }
    
    /// Whether on-device offline recognition is supported
    var supportsOnDeviceRecognition: Bool { get }
    
    /// Requests user authorization for speech recognition
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    
    /// Starts live speech recognition from an incoming stream of PCM buffers
    func startLiveTranscription(audioBufferStream: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<LiveTranscriptChunk, Error>
    
    /// Terminates the active live transcription session
    func stopLiveTranscription()
    
    /// Transcribes a completed audio file asynchronously and returns timestamped segments
    func transcribeAudioFile(at url: URL) async throws -> [LiveTranscriptSegment]
}
