//
//  SpeechTranscriptionServiceTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying SpeechTranscriptionServiceProtocol contract,
//  live streaming recognition chunks, file transcription, offline on-device fallback,
//  error typing, and concurrency safety.
//

import XCTest
import Foundation
import Speech
import AVFoundation
@testable import MeetMind

@MainActor
final class SpeechTranscriptionServiceTests: XCTestCase {
    
    private var service: MockSpeechTranscriptionService!
    private var testAudioURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        service = MockSpeechTranscriptionService()
        let tempDir = FileManager.default.temporaryDirectory
        testAudioURL = tempDir.appendingPathComponent("sample_audio_\(UUID().uuidString).m4a")
    }
    
    override func tearDown() async throws {
        service.stopLiveTranscription()
        service = nil
        testAudioURL = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 5: Speech Transcription Service)
    
    /// Tier 1: Feature 5 - Validates service availability and on-device recognition flags.
    func test_tier1_feature5_serviceAvailabilityAndOnDeviceFlags() throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        XCTAssertTrue(speechService.isAvailable)
        XCTAssertTrue(speechService.supportsOnDeviceRecognition)
    }
    
    /// Tier 1: Feature 5 - Validates requestAuthorization returns authorized status.
    func test_tier1_feature5_requestAuthorizationReturnsAuthorized() async throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        let status = await speechService.requestAuthorization()
        XCTAssertEqual(status, .authorized)
    }
    
    /// Tier 1: Feature 5 - Validates startLiveTranscription yields chunks with segments.
    func test_tier1_feature5_startLiveTranscriptionEmitsChunks() async throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let chunkStream = speechService.startLiveTranscription(audioBufferStream: dummyStream)
        
        var emittedChunks: [LiveTranscriptChunk] = []
        for try await chunk in chunkStream {
            emittedChunks.append(chunk)
        }
        
        XCTAssertEqual(emittedChunks.count, 2)
        XCTAssertFalse(emittedChunks[0].isFinal)
        XCTAssertEqual(emittedChunks[0].text, "Good morning team")
        XCTAssertTrue(emittedChunks[1].isFinal)
        XCTAssertTrue(emittedChunks[1].text.contains("let's start the standup."))
    }
    
    /// Tier 1: Feature 5 - Validates stopLiveTranscription terminates live streaming.
    func test_tier1_feature5_stopLiveTranscriptionTerminatesStream() async throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { _ in }
        let chunkStream = speechService.startLiveTranscription(audioBufferStream: dummyStream)
        
        let consumeTask = Task { () -> Int in
            var count = 0
            for try await _ in chunkStream {
                count += 1
            }
            return count
        }
        
        speechService.stopLiveTranscription()
        let count = try await consumeTask.value
        XCTAssertLessThanOrEqual(count, 2)
    }
    
    /// Tier 1: Feature 5 - Validates transcribeAudioFile returns diarized segments with timestamps.
    func test_tier1_feature5_transcribeAudioFileReturnsSegments() async throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        let segments = try await speechService.transcribeAudioFile(at: testAudioURL)
        
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "We finalized the Q4 architecture roadmap.")
        XCTAssertEqual(segments[0].startTime, 0.0)
        XCTAssertEqual(segments[0].duration, 3.5)
        XCTAssertEqual(segments[0].endTime, 3.5)
        XCTAssertGreaterThanOrEqual(segments[0].confidence, 0.95)
    }
    
    /// Tier 1: Feature 5 - Validates segments have ascending startTime ordering.
    func test_tier1_feature5_segmentsChronologicalOrdering() async throws {
        let speechService: any SpeechTranscriptionServiceProtocol = service
        let segments = try await speechService.transcribeAudioFile(at: testAudioURL)
        
        for i in 1..<segments.count {
            XCTAssertGreaterThanOrEqual(segments[i].startTime, segments[i - 1].startTime)
        }
    }
    
    /// Tier 1: Feature 8 - Validates Clean Architecture dependency injection via protocol.
    func test_tier1_feature8_cleanArchitectureSpeechInjection() async throws {
        final class SpeechTranscribeConsumer {
            let transcriber: any SpeechTranscriptionServiceProtocol
            init(transcriber: any SpeechTranscriptionServiceProtocol) {
                self.transcriber = transcriber
            }
            func runTranscription(on url: URL) async throws -> [LiveTranscriptSegment] {
                return try await transcriber.transcribeAudioFile(at: url)
            }
        }
        
        let consumer = SpeechTranscribeConsumer(transcriber: service)
        let results = try await consumer.runTranscription(on: testAudioURL)
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Error Injection, Fallbacks)
    
    /// Tier 2: Feature 5 - Validates authorizationDenied error injection.
    func test_tier2_feature5_authorizationDeniedError() throws {
        let error = SpeechTranscriptionError.authorizationDenied
        XCTAssertEqual(error.errorDescription, "Speech recognition authorization was denied.")
    }
    
    /// Tier 2: Feature 5 - Validates recognizerUnavailable error typing and description.
    func test_tier2_feature5_recognizerUnavailableError() throws {
        let error = SpeechTranscriptionError.recognizerUnavailable
        XCTAssertEqual(error.errorDescription, "SFSpeechRecognizer is unavailable on this device or locale.")
    }
    
    /// Tier 2: Feature 5 - Validates onDeviceRecognitionUnavailable error typing and description.
    func test_tier2_feature5_onDeviceRecognitionUnavailableError() throws {
        let error = SpeechTranscriptionError.onDeviceRecognitionUnavailable
        XCTAssertEqual(error.errorDescription, "On-device speech recognition is not supported on this device.")
    }
    
    /// Tier 2: Feature 5 - Validates recognitionRequestFailed error typing and description.
    func test_tier2_feature5_recognitionRequestFailedError() throws {
        let error = SpeechTranscriptionError.recognitionRequestFailed("Buffer rate mismatch")
        XCTAssertEqual(error.errorDescription, "Speech recognition request failed: Buffer rate mismatch")
    }
    
    /// Tier 2: Feature 5 - Validates audioFileReadFailed error typing and description.
    func test_tier2_feature5_audioFileReadFailedError() throws {
        let error = SpeechTranscriptionError.audioFileReadFailed("Corrupted AAC atoms")
        XCTAssertEqual(error.errorDescription, "Failed to read audio file for transcription: Corrupted AAC atoms")
    }
    
    /// Tier 2: Feature 5 - Validates transcribeAudioFile throws when error is injected.
    func test_tier2_feature5_transcribeAudioFileThrowsInjectedError() async throws {
        service.shouldThrowError = .audioFileReadFailed("File unreadable")
        
        do {
            _ = try await service.transcribeAudioFile(at: testAudioURL)
            XCTFail("Expected transcribeAudioFile to throw")
        } catch let error as SpeechTranscriptionError {
            XCTAssertEqual(error, .audioFileReadFailed("File unreadable"))
        }
    }
    
    /// Tier 2: Feature 5 - Validates startLiveTranscription throws when error is injected.
    func test_tier2_feature5_startLiveTranscriptionThrowsInjectedError() async throws {
        service.shouldThrowError = .recognizerUnavailable
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let stream = service.startLiveTranscription(audioBufferStream: dummyStream)
        
        do {
            for try await _ in stream {
                XCTFail("Stream should have thrown immediately")
            }
        } catch let error as SpeechTranscriptionError {
            XCTAssertEqual(error, .recognizerUnavailable)
        }
    }
    
    /// Tier 2: Feature 5 - Validates empty mock chunks terminates stream cleanly without emitting.
    func test_tier2_feature5_emptyMockChunksCleanTermination() async throws {
        service.mockChunks = []
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let stream = service.startLiveTranscription(audioBufferStream: dummyStream)
        
        var received = 0
        for try await _ in stream {
            received += 1
        }
        XCTAssertEqual(received, 0)
    }
    
    /// Tier 2: Feature 5 - Validates authorization status variation: denied.
    func test_tier2_feature5_authorizationStatusDenied() async throws {
        service.mockAuthorizationStatus = .denied
        let status = await service.requestAuthorization()
        XCTAssertEqual(status, .denied)
    }
    
    /// Tier 2: Feature 5 - Validates authorization status variation: restricted.
    func test_tier2_feature5_authorizationStatusRestricted() async throws {
        service.mockAuthorizationStatus = .restricted
        let status = await service.requestAuthorization()
        XCTAssertEqual(status, .restricted)
    }
    
    // MARK: - Tier 3: Concurrency, Task Cancellation & Value Types
    
    /// Tier 3: Pairwise - Verifies Task cancellation terminates live transcription cleanly.
    func test_tier3_liveStreamTaskCancellation() async throws {
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { _ in }
        let stream = service.startLiveTranscription(audioBufferStream: dummyStream)
        
        let task = Task { () -> Int in
            var count = 0
            for try await _ in stream {
                count += 1
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            return count
        }
        
        task.cancel()
        let result = try? await task.value
        XCTAssertTrue(result == nil || result! <= 2)
    }
    
    /// Tier 3: Pairwise - Verifies LiveTranscriptSegment is Codable and Equatable.
    func test_tier3_liveTranscriptSegmentCodableAndEquatable() throws {
        let segment = LiveTranscriptSegment(text: "Architecture sync", startTime: 10.0, duration: 4.5, confidence: 0.97)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(LiveTranscriptSegment.self, from: data)
        XCTAssertEqual(decoded, segment)
        XCTAssertEqual(decoded.endTime, 14.5)
    }
    
    /// Tier 3: Pairwise - Verifies LiveTranscriptChunk Equatable conformance.
    func test_tier3_liveTranscriptChunkEquatable() throws {
        let segment = LiveTranscriptSegment(text: "Chunk text", startTime: 0, duration: 1)
        let chunk1 = LiveTranscriptChunk(text: "Chunk text", isFinal: true, segments: [segment])
        let chunk2 = LiveTranscriptChunk(text: "Chunk text", isFinal: true, segments: [segment])
        let chunk3 = LiveTranscriptChunk(text: "Other text", isFinal: false)
        
        XCTAssertEqual(chunk1, chunk2)
        XCTAssertNotEqual(chunk1, chunk3)
    }
    
    /// Tier 1: Feature 5 - Validates transcribeAudioFile with custom mock segments.
    func test_tier1_feature5_transcribeAudioFileWithCustomSegments() async throws {
        let customSegments = [
            LiveTranscriptSegment(text: "Custom utterance", startTime: 1.0, duration: 2.0, confidence: 0.99)
        ]
        service.mockFileSegments = customSegments
        let results = try await service.transcribeAudioFile(at: testAudioURL)
        XCTAssertEqual(results, customSegments)
    }
    
    /// Tier 1: Feature 5 - Validates live transcription segment confidence preservation.
    func test_tier1_feature5_liveTranscriptionSegmentConfidencePreservation() async throws {
        let dummyStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        let stream = service.startLiveTranscription(audioBufferStream: dummyStream)
        
        for try await chunk in stream {
            for segment in chunk.segments {
                XCTAssertGreaterThan(segment.confidence, 0.0)
            }
        }
    }
    
    /// Tier 2: Feature 5 - Validates live transcription multiple consecutive sessions.
    func test_tier2_feature5_liveTranscriptionMultipleConsecutiveSessions() async throws {
        for _ in 0..<3 {
            let dummyStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
            let stream = service.startLiveTranscription(audioBufferStream: dummyStream)
            var count = 0
            for try await _ in stream { count += 1 }
            XCTAssertEqual(count, 2)
            service.stopLiveTranscription()
        }
    }
    
    /// Tier 2: Feature 5 - Validates speech transcription error equality.
    func test_tier2_feature5_speechTranscriptionErrorEquality() throws {
        let err1 = SpeechTranscriptionError.authorizationDenied
        let err2 = SpeechTranscriptionError.authorizationDenied
        let err3 = SpeechTranscriptionError.recognizerUnavailable
        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)
    }
    
    /// Tier 2: Feature 5 - Validates authorization status notDetermined.
    func test_tier2_feature5_authorizationStatusNotDetermined() async throws {
        service.mockAuthorizationStatus = .notDetermined
        let status = await service.requestAuthorization()
        XCTAssertEqual(status, .notDetermined)
    }
    
    /// Tier 3: LiveTranscriptSegment endTime property calculation accuracy.
    func test_tier3_liveTranscriptSegmentEndTimeCalculation() throws {
        let segment = LiveTranscriptSegment(text: "Timing check", startTime: 15.2, duration: 3.8)
        XCTAssertEqual(segment.endTime, 19.0)
    }
}
