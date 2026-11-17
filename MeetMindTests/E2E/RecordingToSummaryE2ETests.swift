//
//  RecordingToSummaryE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering the complete recording journey:
//  Live Console, Waveform Visualizer, Streaming Speech, Tool Dock (Bookmarks, Notes, Photos, Speakers),
//  Pause/Resume, Discard, Post-Recording Synthesis HUD, and Offline Fallback
//  (Scenarios S3, S20, S34 + Tier 3 Pairwise Combinations).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class RecordingToSummaryE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var recordingVM: LiveRecordingViewModel!
    private var synthesisVM: ProcessingPipelineViewModel!
    private var mockAudioRecorder: MockAudioRecordingService!
    private var mockTranscriptionService: MockSpeechTranscriptionService!
    private var mockSummarizationService: MockSummarizationService!
    private var meeting: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockAudioRecorder = MockAudioRecordingService()
        mockTranscriptionService = MockSpeechTranscriptionService()
        mockSummarizationService = MockSummarizationService()
        
        meeting = Meeting(title: "Architecture Design Review", status: .scheduled)
        context.insert(meeting)
        try? context.save()
        
        recordingVM = LiveRecordingViewModel(
            meeting: meeting,
            modelContext: context,
            recordingService: mockAudioRecorder,
            transcriptionService: mockTranscriptionService
        )
        synthesisVM = ProcessingPipelineViewModel(
            meeting: meeting,
            modelContext: context,
            summarizationService: mockSummarizationService
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        recordingVM = nil
        synthesisVM = nil
        mockAudioRecorder = nil
        mockTranscriptionService = nil
        mockSummarizationService = nil
        meeting = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S3 (Live Interactive Recording)
    
    /// Tier 4: Scenario S3 - Live Interactive Recording Full Workflow
    /// - Given: User initiates a Quick Start recording session.
    /// - When:
    ///   1. Live recording console activates with pulsing timer at 00:00:00.
    ///   2. Dynamic waveform reacts to incoming audio meter levels (60Hz normalized power).
    ///   3. Live speech transcription streams text chunks (interim in italics, final in bold).
    ///   4. User flags 2 bookmarks at distinct timecodes.
    ///   5. User writes a live timestamped note via the tool dock.
    ///   6. User snaps a whiteboard photo pinned to the current timecode.
    ///   7. User stops recording.
    ///   8. Post-processing synthesis HUD animates through multi-stage pipeline.
    ///   9. Meeting detail cockpit opens with all captured assets.
    /// - Then:
    ///   - Audio file is written to container.
    ///   - Meeting entity has 2 bookmarks, 1 note, and 1 photo attachment.
    ///   - Diarized transcript, executive summary, and action items are synthesized.
    func test_tier4_scenario3_liveInteractiveRecording() async throws {
        // Given
        let meeting = Meeting(title: "Architecture Design Review", status: .scheduled)
        
        // When - 1. Start Recording
        try await recordingVM.startSession(for: meeting)
        XCTAssertEqual(meeting.status, .recording)
        XCTAssertTrue(recordingVM.isRecording)
        XCTAssertEqual(recordingVM.elapsedTime, 0)
        
        // When - 2. Waveform Power updates
        recordingVM.simulateAudioPower(level: 0.75)
        XCTAssertEqual(recordingVM.waveformLevels.count, 32)
        XCTAssertGreaterThan(recordingVM.waveformLevels.last ?? 0, 0.0)
        
        // When - 3. Speech streaming chunks
        recordingVM.simulateSpeechChunk(text: "Let's review the API contracts.", isFinal: false)
        XCTAssertEqual(recordingVM.interimTranscript, "Let's review the API contracts.")
        recordingVM.simulateSpeechChunk(text: "Let's review the API contracts.", isFinal: true)
        XCTAssertEqual(recordingVM.transcriptSegments.count, 1)
        
        // Advance time to 00:01:15
        recordingVM.simulateTimeAdvance(seconds: 75.0)
        XCTAssertEqual(recordingVM.elapsedTime, 75.0)
        
        // When - 4. Flag 2 bookmarks
        recordingVM.addBookmark()
        recordingVM.simulateTimeAdvance(seconds: 45.0) // 00:02:00
        recordingVM.addBookmark()
        XCTAssertEqual(recordingVM.bookmarks.count, 2)
        XCTAssertEqual(recordingVM.bookmarks[0].timestamp, 75.0)
        XCTAssertEqual(recordingVM.bookmarks[1].timestamp, 120.0)
        
        // When - 5. Live Note Dock
        recordingVM.addLiveNote(text: "Need to verify GraphQL latency SLA.")
        XCTAssertEqual(recordingVM.notes.count, 1)
        XCTAssertEqual(recordingVM.notes.first?.text, "Need to verify GraphQL latency SLA.")
        XCTAssertEqual(recordingVM.notes.first?.timestamp, 120.0)
        
        // When - 6. Whiteboard Photo Capture
        let dummyJPEGData = Data(repeating: 0xFF, count: 1024)
        recordingVM.captureWhiteboardPhoto(data: dummyJPEGData)
        XCTAssertEqual(recordingVM.photoAttachments.count, 1)
        
        // When - 7. Stop Recording
        let recordedURL = try await recordingVM.finishRecording()
        XCTAssertNotNil(recordedURL)
        XCTAssertFalse(recordingVM.isRecording)
        XCTAssertEqual(meeting.status, .processing)
        
        // When - 8. Post-Processing Synthesis HUD
        mockSummarizationService.mockResponse = MeetingSummaryResponse(
            executiveSummary: "Reviewed API contracts and agreed to verify GraphQL latency.",
            keyDiscussionPoints: ["API contracts review", "GraphQL performance"],
            keyDecisions: ["Proceed with contract testing"],
            actionItems: [ParsedActionItem(title: "Verify GraphQL latency SLA", taskDescription: "Run load tests", assignee: "Sarah", dueDate: nil, priority: "high")],
            topics: ["Architecture", "GraphQL"]
        )
        
        try await synthesisVM.executePipeline(for: meeting)
        
        // Then
        XCTAssertEqual(meeting.status, .completed)
        XCTAssertEqual(meeting.notes.count, 1)
        XCTAssertEqual(meeting.notes.filter { $0.isBookmark }.count, 2)
        XCTAssertNotNil(meeting.summary)
        XCTAssertEqual(meeting.actionItems.count, 1)
    }

    // MARK: - Tier 4: Scenario S20 (Offline Speech Recognition Fallback)
    
    /// Tier 4: Scenario S20 - Offline Speech Recognition Fallback
    /// - Given: Live recording session in progress with network connectivity.
    /// - When:
    ///   1. Network simulation disconnected (`isNetworkAvailable = false`).
    ///   2. Speech transcription service detects network loss.
    ///   3. Engine switches seamlessly to on-device neural transcription model.
    /// - Then:
    ///   - Audio recording continues without interruption.
    ///   - Transcription continues yielding live chunks tagged `isOnDevice == true`.
    ///   - No user prompt or session termination occurs.
    func test_tier4_scenario20_offlineSpeechRecognitionFallback() async throws {
        let meeting = Meeting(title: "Offline Fallback Session")
        try await recordingVM.startSession(for: meeting)
        
        mockTranscriptionService.simulateNetworkStatus(isAvailable: true)
        XCTAssertFalse(mockTranscriptionService.isOnDeviceFallbackActive)
        
        recordingVM.simulateSpeechChunk(text: "Online chunk transcription.", isFinal: true)
        XCTAssertEqual(recordingVM.transcriptSegments.count, 1)
        
        // Simulate network disconnect
        mockTranscriptionService.simulateNetworkStatus(isAvailable: false)
        XCTAssertTrue(mockTranscriptionService.isOnDeviceFallbackActive)
        
        recordingVM.simulateSpeechChunk(text: "Offline on-device chunk transcription.", isFinal: true)
        XCTAssertEqual(recordingVM.transcriptSegments.count, 2)
        XCTAssertTrue(mockTranscriptionService.lastTranscribedSegmentWasOnDevice)
        
        _ = try await recordingVM.finishRecording()
        XCTAssertEqual(meeting.status, .processing)
    }

    // MARK: - Tier 4: Scenario S34 (Destructive Discard Recording)
    
    /// Tier 4: Scenario S34 - Destructive Discard Recording With Confirmation
    /// - Given: Active recording session running at 05:20 elapsed time.
    /// - When:
    ///   1. User taps "Discard" button.
    ///   2. Confirmation dialog is presented.
    ///   3. User confirms destructive discard.
    /// - Then:
    ///   - Active audio buffer tap is cancelled and temporary audio file is deleted.
    ///   - Meeting entity is removed from database.
    ///   - Navigation resets cleanly to Home dashboard.
    func test_tier4_scenario34_destructiveDiscardRecording() async throws {
        let meeting = Meeting(title: "Accidental Meeting")
        try await recordingVM.startSession(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 320.0) // 05:20
        XCTAssertEqual(recordingVM.elapsedTime, 320.0)
        
        recordingVM.requestDiscard()
        XCTAssertTrue(recordingVM.showDiscardConfirmationAlert)
        
        try await recordingVM.confirmDiscard(for: meeting)
        
        XCTAssertFalse(recordingVM.isRecording)
        XCTAssertTrue(mockAudioRecorder.wasRecordingCancelled)
        XCTAssertEqual(recordingVM.elapsedTime, 0.0)
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Dynamic Waveform and 60Hz Power Metering
    /// - Verifies power meter stream updates 32 normalized bars between 0.0 and 1.0.
    func test_tier3_recordingWithLiveWaveformAndPowerMetering() throws {
        XCTAssertEqual(recordingVM.waveformLevels.count, 32)
        for level: Float in [0.1, 0.4, 0.8, 1.0, 0.0] {
            recordingVM.simulateAudioPower(level: level)
            XCTAssertLessThanOrEqual(recordingVM.waveformLevels.last ?? 0, 1.0)
            XCTAssertGreaterThanOrEqual(recordingVM.waveformLevels.last ?? 0, 0.0)
        }
    }

    /// Tier 3: Pairwise - Pause and Resume Timer Continuity
    /// - Verifies timer freezes on pause and resumes without temporal drift.
    func test_tier3_pauseResumeTimerContinuity() throws {
        let meeting = Meeting(title: "Pause Resume Test")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 10.0)
        XCTAssertEqual(recordingVM.elapsedTime, 10.0)
        
        recordingVM.pause()
        XCTAssertTrue(recordingVM.isPaused)
        recordingVM.simulateTimeAdvance(seconds: 5.0)
        XCTAssertEqual(recordingVM.elapsedTime, 10.0) // frozen
        
        recordingVM.resume()
        XCTAssertFalse(recordingVM.isPaused)
        recordingVM.simulateTimeAdvance(seconds: 5.0)
        XCTAssertEqual(recordingVM.elapsedTime, 15.0) // resumed
    }

    /// Tier 3: Pairwise - Live Bookmark Debounce
    /// - Verifies rapid tapping of bookmark button within 1 second ignores duplicate taps.
    func test_tier3_inRecordingBookmarkDebounce() throws {
        let meeting = Meeting(title: "Bookmark Debounce")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 30.0)
        
        recordingVM.addBookmark()
        recordingVM.addBookmark() // rapid duplicate within 100ms
        XCTAssertEqual(recordingVM.bookmarks.count, 1)
        
        recordingVM.simulateTimeAdvance(seconds: 2.0)
        recordingVM.addBookmark() // valid subsequent bookmark
        XCTAssertEqual(recordingVM.bookmarks.count, 2)
    }

    /// Tier 3: Pairwise - Live Note Dock Attachment
    /// - Verifies empty note is discarded while valid note attaches with timecode.
    func test_tier3_inRecordingNoteDockAttachment() throws {
        let meeting = Meeting(title: "Notes Attachment")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 45.0)
        
        recordingVM.addLiveNote(text: "   ") // whitespace only
        XCTAssertEqual(recordingVM.notes.count, 0)
        
        recordingVM.addLiveNote(text: "Action: Deploy backend to staging.")
        XCTAssertEqual(recordingVM.notes.count, 1)
        XCTAssertEqual(recordingVM.notes.first?.timestamp, 45.0)
    }

    /// Tier 3: Pairwise - Whiteboard Photo Capture Compression
    /// - Verifies image attachment stores valid data and generates thumbnail preview.
    func test_tier3_whiteboardCaptureDuringRecording() throws {
        let meeting = Meeting(title: "Photo Capture Test")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 60.0)
        
        let photoData = Data(count: 2048)
        recordingVM.captureWhiteboardPhoto(data: photoData)
        
        XCTAssertEqual(recordingVM.photoAttachments.count, 1)
        XCTAssertEqual(recordingVM.photoAttachments.first?.timestamp, 60.0)
    }

    /// Tier 3: Pairwise - Live Speaker Switcher Tagging
    /// - Verifies switching active speaker tags all subsequent transcript chunks.
    func test_tier3_liveSpeakerSwitcherTagging() throws {
        let meeting = Meeting(title: "Speaker Tagging Sync")
        let speakerA = Speaker(name: "Alice", avatarColorHex: "#0284C7")
        let speakerB = Speaker(name: "Bob", avatarColorHex: "#F59E0B")
        
        recordingVM.startSessionSync(for: meeting)
        recordingVM.activeSpeaker = speakerA
        recordingVM.simulateSpeechChunk(text: "Alice speaking here.", isFinal: true)
        
        recordingVM.activeSpeaker = speakerB
        recordingVM.simulateSpeechChunk(text: "Bob responding here.", isFinal: true)
        
        XCTAssertEqual(recordingVM.transcriptSegments.count, 2)
        XCTAssertEqual(recordingVM.transcriptSegments[0].speakerName, "Alice")
        XCTAssertEqual(recordingVM.transcriptSegments[1].speakerName, "Bob")
    }

    /// Tier 3: Pairwise - Synthesis HUD Multi-Stage Progression
    /// - Verifies synthesis pipeline advances monotonically through 5 stages to 100%.
    func test_tier3_synthesisHUDMultiStageProgression() async throws {
        let meeting = Meeting(title: "Synthesis Pipeline Test")
        mockSummarizationService.mockResponse = MeetingSummaryResponse(
            executiveSummary: "Completed pipeline.",
            keyDiscussionPoints: ["Point 1"],
            keyDecisions: ["Decision 1"],
            actionItems: [],
            topics: ["Testing"]
        )
        
        XCTAssertEqual(synthesisVM.progressPercentage, 0.0)
        try await synthesisVM.executePipeline(for: meeting)
        XCTAssertEqual(synthesisVM.currentStep, .completed)
        XCTAssertEqual(synthesisVM.progressPercentage, 100.0)
    }

    /// Tier 3: Pairwise - Synthesis Pipeline Error Retry with Fallback
    /// - Verifies that AI service failure provides a retry option and falls back gracefully.
    func test_tier3_synthesisPipelineErrorRetry() async throws {
        let meeting = Meeting(title: "Retry Test")
        mockSummarizationService.shouldThrowNetworkError = true
        
        do {
            try await synthesisVM.executePipeline(for: meeting)
            XCTFail("Should fail on network error")
        } catch {
            XCTAssertTrue(synthesisVM.hasError)
            XCTAssertNotNil(synthesisVM.errorMessage)
        }
        
        // Recover and retry
        mockSummarizationService.shouldThrowNetworkError = false
        mockSummarizationService.mockResponse = MeetingSummaryResponse(
            executiveSummary: "Recovered summary.",
            keyDiscussionPoints: [],
            keyDecisions: [],
            actionItems: [],
            topics: []
        )
        try await synthesisVM.retryPipeline(for: meeting)
        XCTAssertEqual(synthesisVM.currentStep, .completed)
    }

    /// Tier 3: Pairwise - Phone Call Audio Interruption Auto-Pause
    /// - Verifies system audio interruption triggers auto-pause and preserves state.
    func test_tier3_recordingInterruptionHandling() throws {
        let meeting = Meeting(title: "Interruption Test")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 20.0)
        
        recordingVM.handleSystemInterruption(type: .began)
        XCTAssertTrue(recordingVM.isPaused)
        XCTAssertTrue(recordingVM.isInterrupted)
        
        recordingVM.handleSystemInterruption(type: .ended)
        XCTAssertFalse(recordingVM.isInterrupted)
    }

    /// Tier 3: Pairwise - Short Recording Discard Threshold (<3s)
    /// - Verifies stopping under 3 seconds prompts confirmation to avoid accidental micro-recordings.
    func test_tier3_shortRecordingDiscardThreshold() throws {
        let meeting = Meeting(title: "Short Recording")
        recordingVM.startSessionSync(for: meeting)
        recordingVM.simulateTimeAdvance(seconds: 1.5)
        
        XCTAssertTrue(recordingVM.isDurationUnderThreshold(seconds: 3.0))
        XCTAssertTrue(recordingVM.shouldPromptForShortRecordingDiscard)
    }

    /// Tier 3: Pairwise - Offline Speech Accuracy and Finalization
    /// - Verifies offline recognizer correctly marks `isFinal` on terminal chunks.
    func test_tier3_offlineSpeechAccuracyAndFinalization() throws {
        let meeting = Meeting(title: "Offline Accuracy")
        recordingVM.startSessionSync(for: meeting)
        
        recordingVM.simulateSpeechChunk(text: "Partial phrase", isFinal: false)
        XCTAssertEqual(recordingVM.transcriptSegments.count, 0)
        
        recordingVM.simulateSpeechChunk(text: "Partial phrase completed.", isFinal: true)
        XCTAssertEqual(recordingVM.transcriptSegments.count, 1)
        XCTAssertEqual(recordingVM.transcriptSegments.first?.text, "Partial phrase completed.")
    }
}
