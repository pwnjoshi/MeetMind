//
//  AudioRecordingServiceTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying AudioRecordingServiceProtocol contract,
//  state machine transitions, RMS meter async streams, duration calculation,
//  cancellation cleanup, error typing, and concurrency safety.
//

import XCTest
import Foundation
import AVFoundation
@testable import MeetMind

final class AudioRecordingServiceTests: XCTestCase {
    
    private var service: MockAudioRecordingService!
    private var testDestinationURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        service = MockAudioRecordingService()
        let tempDir = FileManager.default.temporaryDirectory
        testDestinationURL = tempDir.appendingPathComponent("test_recording_\(UUID().uuidString).m4a")
    }
    
    override func tearDown() async throws {
        if service.state == .recording || service.state == .paused {
            try? service.cancelRecording()
        }
        service = nil
        if FileManager.default.fileExists(atPath: testDestinationURL.path) {
            try? FileManager.default.removeItem(at: testDestinationURL)
        }
        testDestinationURL = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 3: Audio Recording Service)
    
    /// Tier 1: Feature 3 - Validates initial state is idle with zero duration.
    func test_tier1_feature3_initialStateIsIdle() throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        XCTAssertEqual(recordingService.state, .idle)
        XCTAssertEqual(recordingService.currentDuration, 0.0)
    }
    
    /// Tier 1: Feature 3 - Validates startRecording transitions state to .recording.
    func test_tier1_feature3_startRecordingTransitionsToRecording() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        XCTAssertEqual(recordingService.state, .recording)
        XCTAssertEqual(service.destinationURL, testDestinationURL)
    }
    
    /// Tier 1: Feature 3 - Validates pauseRecording transitions state to .paused.
    func test_tier1_feature3_pauseRecordingTransitionsToPaused() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        try recordingService.pauseRecording()
        XCTAssertEqual(recordingService.state, .paused)
    }
    
    /// Tier 1: Feature 3 - Validates resumeRecording transitions state back to .recording.
    func test_tier1_feature3_resumeRecordingTransitionsToRecording() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        try recordingService.pauseRecording()
        XCTAssertEqual(recordingService.state, .paused)
        
        try recordingService.resumeRecording()
        XCTAssertEqual(recordingService.state, .recording)
    }
    
    /// Tier 1: Feature 3 - Validates stopRecording transitions state to .stopped and returns file URL.
    func test_tier1_feature3_stopRecordingTransitionsToStoppedAndReturnsURL() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        let outputURL = try await recordingService.stopRecording()
        
        XCTAssertEqual(recordingService.state, .stopped)
        XCTAssertEqual(outputURL, testDestinationURL)
    }
    
    /// Tier 1: Feature 3 - Validates cancelRecording resets state to .idle and flags isCancelled.
    func test_tier1_feature3_cancelRecordingResetsToIdleAndSetsCancelled() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        try recordingService.cancelRecording()
        
        XCTAssertEqual(recordingService.state, .idle)
        XCTAssertTrue(service.isCancelled)
        XCTAssertEqual(recordingService.currentDuration, 0.0)
    }
    
    /// Tier 1: Feature 3 - Validates duration increments during active recording.
    func test_tier1_feature3_durationAccumulationDuringRecording() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        
        // Wait 250ms for simulation task ticks
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertGreaterThan(recordingService.currentDuration, 0.0)
    }
    
    /// Tier 1: Feature 3 - Validates duration freezes while paused.
    func test_tier1_feature3_durationFreezesWhilePaused() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        try await Task.sleep(nanoseconds: 150_000_000)
        
        try recordingService.pauseRecording()
        let pausedDuration = recordingService.currentDuration
        
        // Wait another 150ms while paused
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recordingService.currentDuration, pausedDuration)
    }
    
    /// Tier 1: Feature 3 - Validates audio meter stream yields normalized power samples.
    func test_tier1_feature3_audioMeterStreamYieldsNormalizedValues() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        let meterStream = recordingService.audioMeterStream
        
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        
        var receivedSamples: [Float] = []
        let consumerTask = Task {
            for await sample in meterStream {
                receivedSamples.append(sample)
                if receivedSamples.count >= 3 {
                    break
                }
            }
        }
        
        try await consumerTask.value
        XCTAssertGreaterThanOrEqual(receivedSamples.count, 3)
        for sample in receivedSamples {
            XCTAssertGreaterThanOrEqual(sample, 0.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
    }
    
    /// Tier 1: Feature 8 - Validates Clean Architecture dependency injection via protocol.
    func test_tier1_feature8_cleanArchitectureProtocolInjection() async throws {
        final class AudioRecorderConsumer {
            let recorder: any AudioRecordingServiceProtocol
            init(recorder: any AudioRecordingServiceProtocol) {
                self.recorder = recorder
            }
            func executeRecord(to url: URL) async throws -> URL {
                try await recorder.startRecording(destinationURL: url)
                return try await recorder.stopRecording()
            }
        }
        
        let consumer = AudioRecorderConsumer(recorder: service)
        let resultURL = try await consumer.executeRecord(to: testDestinationURL)
        XCTAssertEqual(resultURL, testDestinationURL)
    }
    
    /// Tier 1: Feature 36 - Validates multi-step pause and resume cycle.
    func test_tier1_feature36_pauseAndResumeMultipleCycles() async throws {
        let recordingService: any AudioRecordingServiceProtocol = service
        try await recordingService.startRecording(destinationURL: testDestinationURL)
        
        for _ in 0..<3 {
            try recordingService.pauseRecording()
            XCTAssertEqual(recordingService.state, .paused)
            try recordingService.resumeRecording()
            XCTAssertEqual(recordingService.state, .recording)
        }
        
        let finalURL = try await recordingService.stopRecording()
        XCTAssertEqual(recordingService.state, .stopped)
        XCTAssertEqual(finalURL, testDestinationURL)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Error Injection & Robustness)
    
    /// Tier 2: Feature 3 - Validates permissionDenied error injection and typing.
    func test_tier2_feature3_permissionDeniedErrorInjection() async throws {
        service.shouldThrowError = .permissionDenied
        
        do {
            try await service.startRecording(destinationURL: testDestinationURL)
            XCTFail("Expected startRecording to throw permissionDenied")
        } catch let error as AudioRecordingError {
            XCTAssertEqual(error, .permissionDenied)
            XCTAssertEqual(error.errorDescription, "Microphone permission was denied by the user.")
        }
    }
    
    /// Tier 2: Feature 3 - Validates audioSessionSetupFailed error typing and description.
    func test_tier2_feature3_audioSessionSetupFailedError() throws {
        let error = AudioRecordingError.audioSessionSetupFailed("Category conflict")
        XCTAssertEqual(error.errorDescription, "Failed to configure audio session: Category conflict")
    }
    
    /// Tier 2: Feature 3 - Validates engineStartFailed error typing and description.
    func test_tier2_feature3_engineStartFailedError() throws {
        let error = AudioRecordingError.engineStartFailed("HAL device error")
        XCTAssertEqual(error.errorDescription, "AVAudioEngine failed to start: HAL device error")
    }
    
    /// Tier 2: Feature 3 - Validates inputNodeUnavailable error typing and description.
    func test_tier2_feature3_inputNodeUnavailableError() throws {
        let error = AudioRecordingError.inputNodeUnavailable
        XCTAssertEqual(error.errorDescription, "Audio input node is not available on this device.")
    }
    
    /// Tier 2: Feature 3 - Validates fileCreationFailed error typing and description.
    func test_tier2_feature3_fileCreationFailedError() throws {
        let error = AudioRecordingError.fileCreationFailed("Permission denied in sandbox")
        XCTAssertEqual(error.errorDescription, "Could not create destination audio file: Permission denied in sandbox")
    }
    
    /// Tier 2: Feature 3 - Validates invalidState error typing and description.
    func test_tier2_feature3_invalidStateError() throws {
        let error = AudioRecordingError.invalidState("Cannot pause when idle")
        XCTAssertEqual(error.errorDescription, "Invalid recording state operation: Cannot pause when idle")
    }
    
    /// Tier 2: Feature 3 - Validates recordingFailed error typing and description.
    func test_tier2_feature3_recordingFailedError() throws {
        let error = AudioRecordingError.recordingFailed("Buffer overflow")
        XCTAssertEqual(error.errorDescription, "Recording session encountered an error: Buffer overflow")
    }
    
    /// Tier 2: Feature 3 - Validates throwing on pause when configured.
    func test_tier2_feature3_throwOnPause() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        service.shouldThrowError = .invalidState("Hardware interrupted")
        
        XCTAssertThrowsError(try service.pauseRecording()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .invalidState("Hardware interrupted"))
        }
    }
    
    /// Tier 2: Feature 3 - Validates throwing on resume when configured.
    func test_tier2_feature3_throwOnResume() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        service.state = .paused
        service.shouldThrowError = .invalidState("Route changed")
        
        XCTAssertThrowsError(try service.resumeRecording()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .invalidState("Route changed"))
        }
    }
    
    /// Tier 2: Feature 3 - Validates throwing on stop when configured.
    func test_tier2_feature3_throwOnStop() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        service.shouldThrowError = .fileCreationFailed("Disk full")
        
        do {
            _ = try await service.stopRecording()
            XCTFail("Expected stopRecording to throw fileCreationFailed")
        } catch let error as AudioRecordingError {
            XCTAssertEqual(error, .fileCreationFailed("Disk full"))
        }
    }
    
    /// Tier 2: Feature 3 - Validates throwing on cancel when configured.
    func test_tier2_feature3_throwOnCancel() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        service.shouldThrowError = .invalidState("Locked")
        
        XCTAssertThrowsError(try service.cancelRecording()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .invalidState("Locked"))
        }
    }
    
    /// Tier 2: Feature 3 - Validates rapid start and stop without pause.
    func test_tier2_feature3_rapidImmediateStartStop() async throws {
        for _ in 0..<5 {
            try await service.startRecording(destinationURL: testDestinationURL)
            XCTAssertEqual(service.state, .recording)
            _ = try await service.stopRecording()
            XCTAssertEqual(service.state, .stopped)
        }
    }
    
    /// Tier 2: Feature 3 - Validates custom simulated power levels stream sequence.
    func test_tier2_feature3_customSimulatedPowerLevels() async throws {
        service.simulatedPowerLevels = [0.25, 0.50, 0.75]
        let meterStream = service.audioMeterStream
        try await service.startRecording(destinationURL: testDestinationURL)
        
        var samples: [Float] = []
        let task = Task {
            for await sample in meterStream {
                samples.append(sample)
                if samples.count >= 3 { break }
            }
        }
        
        try await task.value
        XCTAssertEqual(samples, [0.25, 0.50, 0.75])
    }
    
    /// Tier 2: Feature 3 - Validates empty simulated power levels yields nothing without crashing.
    func test_tier2_feature3_emptySimulatedPowerLevelsSafe() async throws {
        service.simulatedPowerLevels = []
        try await service.startRecording(destinationURL: testDestinationURL)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(service.state, .recording)
        _ = try await service.stopRecording()
    }
    
    // MARK: - Tier 3: Concurrency, Thread Safety & State Machine
    
    /// Tier 3: Pairwise - Verifies thread-safe concurrent property access.
    func test_tier3_concurrentThreadSafety() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = self.service.state
                    _ = self.service.currentDuration
                }
            }
        }
        
        _ = try await service.stopRecording()
        XCTAssertEqual(service.state, .stopped)
    }
    
    /// Tier 3: Pairwise - Verifies stream termination upon recorder cancel.
    func test_tier3_streamTerminationOnCancel() async throws {
        let stream = service.audioMeterStream
        try await service.startRecording(destinationURL: testDestinationURL)
        
        let iterationTask = Task { () -> Int in
            var count = 0
            for await _ in stream {
                count += 1
            }
            return count
        }
        
        try await Task.sleep(nanoseconds: 150_000_000)
        try service.cancelRecording()
        
        let totalCount = await iterationTask.value
        XCTAssertGreaterThanOrEqual(totalCount, 1)
        XCTAssertEqual(service.state, .idle)
    }
    
    /// Tier 3: Pairwise - Verifies RecordingState enum raw values and Codable conformance.
    func test_tier3_recordingStateCodableConformance() throws {
        let states: [RecordingState] = [.idle, .preparing, .recording, .paused, .stopped]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(RecordingState.self, from: data)
            XCTAssertEqual(decoded, state)
            XCTAssertEqual(decoded.rawValue, state.rawValue)
        }
    }
    
    /// Tier 1: Feature 3 - Validates startRecording while already recording updates destination.
    func test_tier1_feature3_startRecordingWhileAlreadyRecordingUpdatesDestination() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        let secondURL = testDestinationURL.deletingLastPathComponent().appendingPathComponent("second.m4a")
        try await service.startRecording(destinationURL: secondURL)
        XCTAssertEqual(service.destinationURL, secondURL)
        XCTAssertEqual(service.state, .recording)
    }
    
    /// Tier 1: Feature 3 - Validates pauseRecording when paused stays paused.
    func test_tier1_feature3_pauseRecordingWhenPausedStaysPaused() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        try service.pauseRecording()
        XCTAssertEqual(service.state, .paused)
        try service.pauseRecording()
        XCTAssertEqual(service.state, .paused)
    }
    
    /// Tier 1: Feature 3 - Validates resumeRecording when already recording stays recording.
    func test_tier1_feature3_resumeRecordingWhenAlreadyRecordingStaysRecording() async throws {
        try await service.startRecording(destinationURL: testDestinationURL)
        XCTAssertEqual(service.state, .recording)
        try service.resumeRecording()
        XCTAssertEqual(service.state, .recording)
    }
    
    /// Tier 2: Feature 3 - Validates RecordingState all enum cases string representations.
    func test_tier2_feature3_recordingStateDisplayNames() throws {
        XCTAssertEqual(RecordingState.idle.rawValue, "idle")
        XCTAssertEqual(RecordingState.preparing.rawValue, "preparing")
        XCTAssertEqual(RecordingState.recording.rawValue, "recording")
        XCTAssertEqual(RecordingState.paused.rawValue, "paused")
        XCTAssertEqual(RecordingState.stopped.rawValue, "stopped")
    }
    
    /// Tier 2: Feature 3 - Validates stopRecording generates default temp URL when destination is nil.
    func test_tier2_feature3_stopRecordingReturnsDefaultTempURLWhenDestinationNil() async throws {
        service.state = .recording
        service.destinationURL = nil
        let url = try await service.stopRecording()
        XCTAssertFalse(url.path.isEmpty)
        XCTAssertEqual(service.state, .stopped)
    }
    
    /// Tier 2: Feature 3 - Validates audio meter stream subscription yields 0.0 upon pause.
    func test_tier2_feature3_audioMeterStreamYieldsZeroOnPause() async throws {
        let stream = service.audioMeterStream
        try await service.startRecording(destinationURL: testDestinationURL)
        
        var received: [Float] = []
        let consumerTask = Task {
            for await val in stream {
                received.append(val)
                if val == 0.0 { break }
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        try service.pauseRecording()
        try await consumerTask.value
        XCTAssertTrue(received.contains(0.0))
    }
}
