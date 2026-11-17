import Foundation
import Speech
import AVFoundation

public final class MockSpeechTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    public var isAvailable: Bool = true
    public var supportsOnDeviceRecognition: Bool = true
    public var mockAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized
    public var shouldThrowError: SpeechTranscriptionError? = nil
    public var isOnDeviceFallbackActive: Bool = false
    public var lastTranscribedSegmentWasOnDevice: Bool = false
    
    public func simulateNetworkStatus(isAvailable: Bool) {
        self.isAvailable = isAvailable
        self.isOnDeviceFallbackActive = !isAvailable
        if !isAvailable {
            self.lastTranscribedSegmentWasOnDevice = true
        }
    }
    
    public var mockChunks: [LiveTranscriptChunk] = [
        LiveTranscriptChunk(text: "Good morning team", isFinal: false, segments: [
            LiveTranscriptSegment(text: "Good morning team", startTime: 0.0, duration: 1.5, confidence: 0.95)
        ]),
        LiveTranscriptChunk(text: "Good morning team, let's start the standup.", isFinal: true, segments: [
            LiveTranscriptSegment(text: "Good morning team", startTime: 0.0, duration: 1.5, confidence: 0.95),
            LiveTranscriptSegment(text: "let's start the standup.", startTime: 1.8, duration: 2.0, confidence: 0.98)
        ])
    ]
    
    public var mockFileSegments: [LiveTranscriptSegment] = [
        LiveTranscriptSegment(text: "We finalized the Q4 architecture roadmap.", startTime: 0.0, duration: 3.5, confidence: 0.98),
        LiveTranscriptSegment(text: "Alice will complete the SwiftData migration by Friday.", startTime: 4.0, duration: 4.2, confidence: 0.99)
    ]
    
    private var streamingTask: Task<Void, Never>?
    
    public init() {}
    
    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        return mockAuthorizationStatus
    }
    
    public func startLiveTranscription(audioBufferStream: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<LiveTranscriptChunk, Error> {
        AsyncThrowingStream { continuation in
            if let error = shouldThrowError {
                continuation.finish(throwing: error)
                return
            }
            
            streamingTask = Task {
                for chunk in mockChunks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            
            continuation.onTermination = { [weak self] _ in
                self?.stopLiveTranscription()
            }
        }
    }
    
    public func stopLiveTranscription() {
        streamingTask?.cancel()
        streamingTask = nil
    }
    
    public func transcribeAudioFile(at url: URL) async throws -> [LiveTranscriptSegment] {
        if let error = shouldThrowError {
            throw error
        }
        return mockFileSegments
    }
}
