import Foundation
import Speech
import AVFoundation

public final class SpeechTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let speechRecognizer: SFSpeechRecognizer?
    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    private let lock = NSLock()
    
    public var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    public var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
    
    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    deinit {
        stopLiveTranscription()
    }
    
    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    public func startLiveTranscription(audioBufferStream: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<LiveTranscriptChunk, Error> {
        AsyncThrowingStream { continuation in
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                continuation.finish(throwing: SpeechTranscriptionError.recognizerUnavailable)
                return
            }
            
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            
            lock.lock()
            self.activeRequest = request
            lock.unlock()
            
            // Background task feeding buffers into recognition request
            Task {
                for await buffer in audioBufferStream {
                    self.lock.lock()
                    let req = self.activeRequest
                    self.lock.unlock()
                    if let req = req {
                        req.append(buffer)
                    } else {
                        break
                    }
                }
                request.endAudio()
            }
            
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.finish(throwing: SpeechTranscriptionError.recognitionRequestFailed(error.localizedDescription))
                    return
                }
                guard let result = result else { return }
                
                let segments = result.bestTranscription.segments.map { seg in
                    LiveTranscriptSegment(
                        text: seg.substring,
                        startTime: seg.timestamp,
                        duration: seg.duration,
                        confidence: seg.confidence
                    )
                }
                
                let chunk = LiveTranscriptChunk(
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal,
                    segments: segments
                )
                continuation.yield(chunk)
                
                if result.isFinal {
                    continuation.finish()
                }
            }
            
            lock.lock()
            self.activeRecognitionTask = task
            lock.unlock()
            
            continuation.onTermination = { [weak self] _ in
                self?.stopLiveTranscription()
            }
        }
    }
    
    public func stopLiveTranscription() {
        lock.lock()
        activeRequest?.endAudio()
        activeRequest = nil
        activeRecognitionTask?.cancel()
        activeRecognitionTask = nil
        lock.unlock()
    }
    
    public func transcribeAudioFile(at url: URL) async throws -> [LiveTranscriptSegment] {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechTranscriptionError.audioFileReadFailed("File not found at \(url.path)")
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        return try await withCheckedThrowingContinuation { continuation in
            let continuationLock = NSLock()
            var hasResumed = false
            
            @Sendable func resumeOnce(with result: Result<[LiveTranscriptSegment], Error>) {
                continuationLock.lock()
                defer { continuationLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    resumeOnce(with: .failure(SpeechTranscriptionError.recognitionRequestFailed(error.localizedDescription)))
                    return
                }
                guard let result = result, result.isFinal else { return }
                
                let segments = result.bestTranscription.segments.map { seg in
                    LiveTranscriptSegment(
                        text: seg.substring,
                        startTime: seg.timestamp,
                        duration: seg.duration,
                        confidence: seg.confidence
                    )
                }
                resumeOnce(with: .success(segments))
            }
        }
    }
}
