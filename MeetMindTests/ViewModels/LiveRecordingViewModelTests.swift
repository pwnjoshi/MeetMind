//
//  LiveRecordingViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Comprehensive test suite covering Live Recording Console HUD, Dynamic Waveform Visualizer,
/// Streaming Speech Transcript Feed, Live In-Recording Note Dock, Bookmarks/Flags, Speaker Switcher,
/// Whiteboard Camera Snaps, Pause/Resume, Stop Finalization, and Discard Confirmation.
/// Corresponds to Features 29, 30, 31, 32, 33, 34, 35, 36, 37, and 38.
@MainActor
final class LiveRecordingViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: LiveRecordingViewModel!
    private var mockAudioService: MockAudioRecordingService!
    private var mockSpeechService: MockSpeechTranscriptionService!
    private var initialMeeting: Meeting!
    private var testAudioURL: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockAudioService = MockAudioRecordingService()
        mockAudioService.automaticallyAdvancesDuration = false
        mockSpeechService = MockSpeechTranscriptionService()
        testAudioURL = URL(fileURLWithPath: "/tmp/live_test_audio_\(UUID().uuidString).m4a")
        
        initialMeeting = Meeting(
            title: "Live Standup",
            createdAt: Date(),
            scheduledStartTime: nil,
            duration: 0,
            status: .recording,
            audioFileURL: testAudioURL,
            isFavorite: false
        )
        context.insert(initialMeeting)
        try? context.save()
        
        sut = LiveRecordingViewModel(
            meeting: initialMeeting,
            modelContext: context,
            recordingService: mockAudioService,
            transcriptionService: mockSpeechService,
            destinationAudioURL: testAudioURL,
            updatesFromRecordingClock: false
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        sut.confirmDiscard()
        sut = nil
        initialMeeting = nil
        mockAudioService = nil
        mockSpeechService = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    private func fetchMeeting(id: UUID) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Tier 1: Feature 29 (Live Recording Console)
    
    /// Tier 1: Feature 29 - Validates start recording initializes console HUD and audio engine.
    func test_tier1_feature29_startSessionHUDInitialization() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        
        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertEqual(sut.elapsedDuration, 0.0)
        XCTAssertEqual(mockAudioService.state, .recording)
        XCTAssertEqual(sut.activeAudioRoute, "Built-In Microphone")
    }
    
    /// Tier 1: Feature 29 - Validates elapsed timer ticks and increments recorded duration.
    func test_tier1_feature29_elapsedTimerIncrementsOverTime() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        
        sut.simulateTimerTick(seconds: 1.0)
        XCTAssertEqual(sut.elapsedDuration, 1.0)
        
        sut.simulateTimerTick(seconds: 14.0)
        XCTAssertEqual(sut.elapsedDuration, 15.0)
    }
    
    /// Tier 1: Feature 29 - Validates formatted duration string rendering in MM:SS format.
    func test_tier1_feature29_formattedDurationStringMMSS() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 125.0) // 2m 5s
        
        XCTAssertEqual(sut.formattedDuration, "02:05")
    }
    
    /// Tier 1: Feature 29 - Validates active microphone route badge display.
    func test_tier1_feature29_activeMicrophoneRouteBadgeDisplay() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertEqual(sut.audioRouteBadgeTitle, "Built-In Mic")
        
        sut.simulateRouteChange(newRoute: "AirPods Pro")
        XCTAssertEqual(sut.audioRouteBadgeTitle, "AirPods Pro")
    }
    
    /// Tier 1: Feature 29 - Validates inline title editing during live recording session.
    func test_tier1_feature29_inlineTitleEditing() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertEqual(sut.meetingTitle, "Live Standup")
        
        sut.updateMeetingTitle("Q4 Engineering Kickoff")
        XCTAssertEqual(sut.meetingTitle, "Q4 Engineering Kickoff")
        
        let stored = fetchMeeting(id: sut.meetingId)
        XCTAssertEqual(stored?.title, "Q4 Engineering Kickoff")
    }
    
    // MARK: - Tier 1: Feature 30 (Live Dynamic Waveform Visualizer)
    
    /// Tier 1: Feature 30 - Validates waveform levels array maintains exactly 32 frequency/power bars.
    func test_tier1_feature30_waveformLevelsPopulates32Bars() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertEqual(sut.waveformLevels.count, 32)
        
        sut.simulateAudioPowerUpdate(power: 0.75)
        XCTAssertEqual(sut.waveformLevels.count, 32)
    }
    
    /// Tier 1: Feature 30 - Validates normalized power levels stay strictly within 0.0 to 1.0.
    func test_tier1_feature30_waveformPowerNormalizationWithinRange() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        
        sut.simulateAudioPowerUpdate(power: 0.42)
        for level in sut.waveformLevels {
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
        }
    }
    
    /// Tier 1: Feature 30 - Validates waveform decays smoothly toward zero baseline during silence.
    func test_tier1_feature30_waveformDecaysOnSilence() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateAudioPowerUpdate(power: 0.9)
        let peakLevel = sut.waveformLevels.first!
        
        // Simulate silence decay over 5 ticks
        for _ in 0..<5 {
            sut.simulateSilenceDecay()
        }
        
        let decayedLevel = sut.waveformLevels.first!
        XCTAssertLessThan(decayedLevel, peakLevel)
    }
    
    // MARK: - Tier 1: Feature 31 (Live Streaming Transcript Feed)
    
    /// Tier 1: Feature 31 - Validates speech streaming chunks accumulate into transcript feed.
    func test_tier1_feature31_streamingTranscriptAccumulatesChunks() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        
        sut.simulateSpeechChunk(text: "Good morning everyone.", isFinal: false)
        XCTAssertEqual(sut.interimTranscriptText, "Good morning everyone.")
        
        sut.simulateSpeechChunk(text: "Good morning everyone. Let's begin the review.", isFinal: true)
        XCTAssertEqual(sut.finalTranscriptSegments.count, 1)
        XCTAssertEqual(sut.finalTranscriptSegments.first?.text, "Good morning everyone. Let's begin the review.")
    }

    /// A partial recognizer hypothesis must remain preview-only; only a unique
    /// final result can enter the provisional live transcript.
    func test_tier1_feature31_receivedFinalChunkCommitsOnce() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()

        let partial = LiveTranscriptChunk(text: "Budget approval is", isFinal: false)
        sut.receiveLiveTranscriptChunk(partial)
        XCTAssertEqual(sut.interimTranscriptText, "Budget approval is")
        XCTAssertTrue(sut.finalTranscriptSegments.isEmpty)

        let final = LiveTranscriptChunk(
            text: "Budget approval is pending.",
            isFinal: true,
            segments: [LiveTranscriptSegment(text: "Budget approval is pending.", startTime: 2, duration: 1, confidence: 0.92)]
        )
        sut.receiveLiveTranscriptChunk(final)
        sut.receiveLiveTranscriptChunk(final)

        XCTAssertEqual(sut.finalTranscriptSegments.count, 1)
        XCTAssertEqual(sut.finalTranscriptSegments.first?.text, "Budget approval is pending.")
        XCTAssertEqual(sut.interimTranscriptText, "")
    }
    
    /// Tier 1: Feature 31 - Validates interim results display in italicized pending state.
    func test_tier1_feature31_interimResultsDisplayAsPending() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateSpeechChunk(text: "We are considering...", isFinal: false)
        
        XCTAssertTrue(sut.hasInterimText)
        XCTAssertEqual(sut.interimTranscriptText, "We are considering...")
    }
    
    /// Tier 1: Feature 31 - Validates final chunk appends segment with speaker tag and confidence.
    func test_tier1_feature31_finalChunkAppendsDiarizedSegment() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.activeSpeaker = "Speaker 1"
        sut.simulateSpeechChunk(text: "Approved the deployment schedule.", isFinal: true)
        
        XCTAssertEqual(sut.finalTranscriptSegments.count, 1)
        let segment = sut.finalTranscriptSegments.first
        XCTAssertEqual(segment?.speakerName, "Speaker 1")
        XCTAssertEqual(segment?.text, "Approved the deployment schedule.")
        XCTAssertGreaterThanOrEqual(segment?.confidence ?? 0.0, 0.9)
    }
    
    /// Tier 1: Feature 31 - Validates transcript segment timestamp matches current session elapsed time.
    func test_tier1_feature31_segmentTimestampMatchesCurrentElapsed() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 45.0)
        
        sut.simulateSpeechChunk(text: "Key point discussed at 45 seconds.", isFinal: true)
        let segment = sut.finalTranscriptSegments.last
        XCTAssertEqual(segment?.endTime, 45.0)
    }
    
    // MARK: - Tier 1: Feature 32 (Live Note-Taking Dock Tool)
    
    /// Tier 1: Feature 32 - Validates opening note sheet stamps current elapsed timecode.
    func test_tier1_feature32_openNoteSheetSetsCaptureTimestamp() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 62.0)
        
        sut.openNoteDock()
        XCTAssertTrue(sut.isNoteSheetPresented)
        XCTAssertEqual(sut.noteCaptureTimestamp, 62.0)
    }
    
    /// Tier 1: Feature 32 - Validates saving note appends to meeting notes list.
    func test_tier1_feature32_saveNoteAppendsToMeetingNotes() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 30.0)
        sut.openNoteDock()
        
        sut.saveNote(text: "Discussed database migration strategy.")
        
        XCTAssertFalse(sut.isNoteSheetPresented)
        XCTAssertEqual(sut.capturedNotes.count, 1)
        XCTAssertEqual(sut.capturedNotes.first?.text, "Discussed database migration strategy.")
        XCTAssertEqual(sut.capturedNotes.first?.timestamp, 30.0)
    }
    
    /// Tier 1: Feature 32 - Validates note count badge increments in action dock.
    func test_tier1_feature32_noteBadgeCountIncrements() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertEqual(sut.notesCount, 0)
        
        sut.saveNote(text: "Note 1")
        sut.saveNote(text: "Note 2")
        
        XCTAssertEqual(sut.notesCount, 2)
    }
    
    // MARK: - Tier 1: Feature 33 (Live Bookmark / Flag Tool)
    
    /// Tier 1: Feature 33 - Validates tapping bookmark captures exact current timecode.
    func test_tier1_feature33_addBookmarkCapturesExactTimecode() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 88.5)
        
        sut.addBookmark()
        
        XCTAssertEqual(sut.bookmarks.count, 1)
        XCTAssertEqual(sut.bookmarks.first?.timestamp, 88.5)
    }
    
    /// Tier 1: Feature 33 - Validates bookmark star indicator triggers highlight state.
    func test_tier1_feature33_bookmarkStarIndicatorHighlights() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertFalse(sut.isBookmarkButtonHighlighted)
        
        sut.addBookmark()
        XCTAssertTrue(sut.isBookmarkButtonHighlighted)
        
        sut.resetBookmarkHighlight()
        XCTAssertFalse(sut.isBookmarkButtonHighlighted)
    }
    
    /// Tier 1: Feature 33 - Validates bookmarks list maintains chronological ascending order.
    func test_tier1_feature33_bookmarksListMaintainsAscendingOrder() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 10.0)
        sut.addBookmark()
        
        sut.simulateTimerTick(seconds: 25.0)
        sut.addBookmark()
        
        XCTAssertEqual(sut.bookmarks.count, 2)
        XCTAssertEqual(sut.bookmarks[0].timestamp, 10.0)
        XCTAssertEqual(sut.bookmarks[1].timestamp, 35.0)
    }
    
    // MARK: - Tier 1: Feature 34 (Live Speaker Tag Switcher)
    
    /// Tier 1: Feature 34 - Validates speaker chip list displays available participants.
    func test_tier1_feature34_speakerChipListDisplaysAvailableSpeakers() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        let speakers = sut.availableSpeakers
        XCTAssertGreaterThanOrEqual(speakers.count, 2)
        XCTAssertEqual(sut.activeSpeakerName, speakers.first?.name)
    }
    
    /// Tier 1: Feature 34 - Validates switching active speaker tags subsequent speech chunks.
    func test_tier1_feature34_switchActiveSpeakerTagsNextSegments() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.switchSpeaker(to: "Alex Rivera")
        XCTAssertEqual(sut.activeSpeakerName, "Alex Rivera")
        
        sut.simulateSpeechChunk(text: "Here is the architectural design.", isFinal: true)
        XCTAssertEqual(sut.finalTranscriptSegments.last?.speakerName, "Alex Rivera")
    }
    
    /// Tier 1: Feature 34 - Validates dynamically adding a new speaker during live recording.
    func test_tier1_feature34_addNewSpeakerDuringRecording() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.addNewSpeaker(name: "David Kim", colorHex: "#F59E0B")
        
        XCTAssertTrue(sut.availableSpeakers.contains(where: { $0.name == "David Kim" }))
        XCTAssertEqual(sut.activeSpeakerName, "David Kim")
    }
    
    // MARK: - Tier 1: Feature 35 (Whiteboard / Media Capture)
    
    /// Tier 1: Feature 35 - Validates attaching whiteboard photo pins image file URL to timestamp.
    func test_tier1_feature35_attachPhotoPinsImageToTimestamp() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 75.0)
        
        let photoURL = URL(fileURLWithPath: "/tmp/whiteboard_snap_1.jpg")
        sut.attachPhoto(url: photoURL)
        
        XCTAssertEqual(sut.capturedPhotos.count, 1)
        XCTAssertEqual(sut.capturedPhotos.first?.url, photoURL)
        XCTAssertEqual(sut.capturedPhotos.first?.timestamp, 75.0)
    }
    
    /// Tier 1: Feature 35 - Validates photo count badge increments in dock.
    func test_tier1_feature35_photoCountBadgeIncrements() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        XCTAssertEqual(sut.photosCount, 0)
        
        sut.attachPhoto(url: URL(fileURLWithPath: "/tmp/p1.jpg"))
        sut.attachPhoto(url: URL(fileURLWithPath: "/tmp/p2.jpg"))
        
        XCTAssertEqual(sut.photosCount, 2)
    }
    
    // MARK: - Tier 1: Feature 36 (Pause & Resume Controls)
    
    /// Tier 1: Feature 36 - Validates pause recording halts audio engine and freezes timer.
    func test_tier1_feature36_pauseRecordingFreezesTimer() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 20.0)
        
        sut.pauseSession()
        XCTAssertEqual(sut.recordingState, .paused)
        XCTAssertEqual(mockAudioService.state, .paused)
        
        // Simulating timer tick during pause should not increase elapsed duration
        sut.simulateTimerTick(seconds: 5.0)
        XCTAssertEqual(sut.elapsedDuration, 20.0)
    }
    
    /// Tier 1: Feature 36 - Validates pause recording updates state to paused.
    func test_tier1_feature36_pauseRecordingUpdatesStateToPaused() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateAudioPowerUpdate(power: 0.9)
        XCTAssertEqual(sut.waveformLevels.first, 0.9)
        
        sut.pauseSession()
        XCTAssertEqual(sut.recordingState, .paused)
        XCTAssertTrue(sut.isPaused)
        XCTAssertEqual(sut.waveformLevels.count, 32)
        XCTAssertEqual(sut.waveformLevels.first, 0.05)
        
        // Power updates while paused must be ignored
        sut.simulateAudioPowerUpdate(power: 0.8)
        XCTAssertEqual(sut.waveformLevels.first, 0.05)
        
        sut.updateWaveformLevels(with: 0.7)
        XCTAssertEqual(sut.waveformLevels.first, 0.05)
    }
    
    /// Tier 1: Feature 36 - Validates resume recording restarts timer from frozen duration.
    func test_tier1_feature36_resumeRecordingRestartsTimer() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 15.0)
        sut.pauseSession()
        
        sut.resumeSession()
        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertEqual(mockAudioService.state, .recording)
        
        sut.simulateTimerTick(seconds: 5.0)
        XCTAssertEqual(sut.elapsedDuration, 20.0)
    }
    
    // MARK: - Tier 1: Feature 37 (Finish / Stop Recording)
    
    /// Tier 1: Feature 37 - Validates stopping recording flushes audio file to disk.
    func test_tier1_feature37_stopRecordingFlushesAudioFile() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 120.0)
        
        mockAudioService.currentDuration = sut.elapsedDuration

        let outputURL = try await sut.stopSession()
        
        XCTAssertEqual(sut.recordingState, .saved)
        XCTAssertEqual(mockAudioService.state, .stopped)
        XCTAssertEqual(outputURL, testAudioURL)
    }
    
    /// Tier 1: Feature 37 - Validates stopping recording advances meeting state to processing.
    func test_tier1_feature37_stopRecordingAdvancesStateToProcessing() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        mockAudioService.currentDuration = sut.elapsedDuration
        _ = try await sut.stopSession()
        
        let updatedMeeting = fetchMeeting(id: sut.meetingId)
        XCTAssertEqual(updatedMeeting?.status, .processing)
    }
    
    // MARK: - Tier 1: Feature 38 (Discard Confirmation Dialog)
    
    /// Tier 1: Feature 38 - Validates discard button presents confirmation alert.
    func test_tier1_feature38_discardButtonPresentsConfirmationAlert() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.requestDiscard()
        
        XCTAssertTrue(sut.isShowingDiscardAlert)
    }
    
    /// Tier 1: Feature 38 - Validates confirming discard cleans up session, deletes audio file, and reverts draft.
    func test_tier1_feature38_confirmDiscardCleansUpSessionAndDeletesFile() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.requestDiscard()
        
        sut.confirmDiscard()
        
        XCTAssertEqual(sut.recordingState, .idle)
        XCTAssertEqual(mockAudioService.state, .idle)
        XCTAssertNil(fetchMeeting(id: sut.meetingId))
        XCTAssertTrue(sut.didCompleteDismissal)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 29: System Interruptions & Routes)
    
    /// Tier 2: Feature 29 - Validates system phone call interruption automatically pauses recording.
    func test_tier2_feature29_backgroundAudioSessionInterruptionAutoPauses() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 40.0)
        
        sut.handleAudioSessionInterruption(began: true)
        
        XCTAssertEqual(sut.recordingState, .interrupted)
        XCTAssertTrue(sut.wasInterruptedBySystem)
        XCTAssertTrue(sut.isInterrupted)
    }
    
    /// Tier 2: Feature 29 - Validates bluetooth route disconnection falls back seamlessly to built-in mic.
    func test_tier2_feature29_bluetoothRouteDisconnectionFallsBackToBuiltInMic() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateRouteChange(newRoute: "AirPods Pro")
        XCTAssertEqual(sut.activeAudioRoute, "AirPods Pro")
        
        sut.simulateRouteChange(newRoute: "Built-In Microphone")
        XCTAssertEqual(sut.activeAudioRoute, "Built-In Microphone")
        XCTAssertEqual(sut.recordingState, .recording)
    }
    
    /// Tier 2: Feature 29 - Validates duration exceeding 1 hour formats as HH:MM:SS.
    func test_tier2_feature29_timerExceedingOneHourFormatsHHMMSS() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 3665.0) // 1h 1m 5s
        
        XCTAssertEqual(sut.formattedDuration, "01:01:05")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 30: Waveform Boundary Math)
    
    /// Tier 2: Feature 30 - Validates power level clipping at 0dB (normalized 1.0 maximum).
    func test_tier2_feature30_waveformPowerClampingAtMax0dB() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateAudioPowerUpdate(power: 2.5) // Out of bounds
        
        XCTAssertEqual(sut.waveformLevels.first, 1.0)
    }
    
    /// Tier 2: Feature 30 - Validates power level clipping at -60dB (normalized 0.0 minimum).
    func test_tier2_feature30_waveformPowerClampingAtMin60dB() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateAudioPowerUpdate(power: -0.5) // Negative out of bounds
        
        XCTAssertEqual(sut.waveformLevels.first, 0.0)
    }
    
    /// Tier 2: Feature 30 - Validates NaN and Infinity protection on power input values.
    func test_tier2_feature30_waveformNaNAndInfinityProtection() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateAudioPowerUpdate(power: Float.nan)
        XCTAssertEqual(sut.waveformLevels.first, 0.0)
        
        sut.simulateAudioPowerUpdate(power: Float.infinity)
        XCTAssertEqual(sut.waveformLevels.first, 0.0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 31: Speech Streaming Stress & Silence)
    
    /// Tier 2: Feature 31 - Validates handling rapid speech stream chunks without loss of text.
    func test_tier2_feature31_rapidStreamingChunksWithoutTextLoss() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        for i in 0..<50 {
            sut.simulateSpeechChunk(text: "Chunk \(i).", isFinal: true)
        }
        
        XCTAssertEqual(sut.finalTranscriptSegments.count, 50)
    }
    
    /// Tier 2: Feature 31 - Validates network failure switches to on-device speech fallback.
    func test_tier2_feature31_offlineSpeechFallbackWhenNetworkDropped() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateNetworkDrop()
        
        XCTAssertTrue(sut.isUsingOnDeviceSpeechFallback)
        XCTAssertTrue(sut.hasOfflineIndicatorPill)
    }
    
    /// Tier 2: Feature 31 - Validates prolonged silence produces zero hallucinated speech segments.
    func test_tier2_feature31_completeSilenceProducesNoHallucinations() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 120.0)
        // No speech emitted
        
        XCTAssertEqual(sut.finalTranscriptSegments.count, 0)
        XCTAssertFalse(sut.hasInterimText)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 32: Notes Validation & Duplicates)
    
    /// Tier 2: Feature 32 - Validates dismissing empty note does not create empty note record.
    func test_tier2_feature32_emptyNoteDismissalDoesNotSave() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.openNoteDock()
        sut.saveNote(text: "   \t  ")
        
        XCTAssertEqual(sut.capturedNotes.count, 0)
    }
    
    /// Tier 2: Feature 32 - Validates multiline note formatting preservation.
    func test_tier2_feature32_multilineNoteTextFormatting() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        let multiline = "Line 1\nLine 2\nLine 3 with bullet: • item"
        sut.saveNote(text: multiline)
        
        XCTAssertEqual(sut.capturedNotes.first?.text, multiline)
    }
    
    /// Tier 2: Feature 32 - Validates capturing multiple notes at identical timestamp.
    func test_tier2_feature32_multipleNotesAtIdenticalTimestamp() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 15.0)
        
        sut.addLiveNote(text: "Note A")
        sut.addLiveNote(text: "Note B")
        
        XCTAssertEqual(sut.capturedNotes.count, 2)
        XCTAssertEqual(sut.capturedNotes[0].timestamp, 15.0)
        XCTAssertEqual(sut.capturedNotes[1].timestamp, 15.0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 33: Bookmark Debounce & Capacity)
    
    /// Tier 2: Feature 33 - Validates debouncing rapid taps (<1 second) on bookmark button.
    func test_tier2_feature33_debounceRapidBookmarkTaps() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 5.0)
        
        sut.addBookmark() // Tapped
        sut.addBookmark() // Rapid double tap within 100ms
        sut.addBookmark() // Rapid triple tap
        
        XCTAssertEqual(sut.bookmarks.count, 1, "Rapid bookmark clicks must be debounced")
    }
    
    /// Tier 2: Feature 33 - Validates maximum bookmark cap at 100 per meeting.
    func test_tier2_feature33_maximumBookmarksCapAtOneHundred() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        for i in 0..<100 {
            sut.simulateTimerTick(seconds: 2.0)
            sut.addBookmark()
        }
        XCTAssertEqual(sut.bookmarks.count, 100)
        
        sut.simulateTimerTick(seconds: 2.0)
        sut.addBookmark() // 101st
        
        XCTAssertEqual(sut.bookmarks.count, 100)
        XCTAssertTrue(sut.isBookmarkLimitReached)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 34: Rapid Speaker Switches)
    
    /// Tier 2: Feature 34 - Validates rapid speaker toggling between speech segments.
    func test_tier2_feature34_rapidSpeakerTogglingBetweenChunks() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.switchSpeaker(to: "Speaker 1")
        sut.simulateSpeechChunk(text: "Segment 1", isFinal: true)
        
        sut.switchSpeaker(to: "Speaker 2")
        sut.simulateSpeechChunk(text: "Segment 2", isFinal: true)
        
        sut.switchSpeaker(to: "Speaker 1")
        sut.simulateSpeechChunk(text: "Segment 3", isFinal: true)
        
        XCTAssertEqual(sut.finalTranscriptSegments[0].speakerName, "Speaker 1")
        XCTAssertEqual(sut.finalTranscriptSegments[1].speakerName, "Speaker 2")
        XCTAssertEqual(sut.finalTranscriptSegments[2].speakerName, "Speaker 1")
    }
    
    /// Tier 2: Feature 34 - Validates default generic speaker name when unassigned.
    func test_tier2_feature34_fallbackGenericSpeakerWhenUnassigned() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.clearActiveSpeaker()
        
        sut.simulateSpeechChunk(text: "Speech without assigned speaker", isFinal: true)
        XCTAssertEqual(sut.finalTranscriptSegments.last?.speakerName, "Speaker 1")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 35: Photo Compression & Permissions)
    
    /// Tier 2: Feature 35 - Validates large photo compression handling.
    func test_tier2_feature35_oversizedPhotoCompressionHandled() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        let largePhotoURL = URL(fileURLWithPath: "/tmp/large_raw_photo.jpg")
        sut.attachPhoto(url: largePhotoURL, originalSizeBytes: 15 * 1024 * 1024)
        
        XCTAssertEqual(sut.capturedPhotos.count, 1)
        XCTAssertTrue(sut.capturedPhotos.first?.isCompressed ?? false)
    }
    
    /// Tier 2: Feature 35 - Validates camera hardware unavailable displays informative alert.
    func test_tier2_feature35_cameraPermissionDeniedDisplaysAlert() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.handleCameraPermissionDenied()
        
        XCTAssertTrue(sut.isShowingCameraPermissionAlert)
        XCTAssertEqual(sut.cameraAlertMessage, "Camera access is required to capture whiteboards.")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 36: Pause/Resume Rapid Cycling)
    
    /// Tier 2: Feature 36 - Validates repeated rapid pause and resume toggling maintains integrity.
    func test_tier2_feature36_repeatedPauseResumeCyclingTogglesCleanly() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        for _ in 0..<20 {
            sut.pauseSession()
            XCTAssertEqual(sut.recordingState, .paused)
            sut.resumeSession()
            XCTAssertEqual(sut.recordingState, .recording)
        }
    }
    
    /// Tier 2: Feature 36 - Validates app pause during background state restoration.
    func test_tier2_feature36_pauseDuringBackgroundStateRestoration() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.pauseSession()
        
        sut.simulateAppDidEnterBackground()
        sut.simulateAppWillEnterForeground()
        
        XCTAssertEqual(sut.recordingState, .paused)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 37: Short Duration Finalization)
    
    /// Tier 2: Feature 37 - Validates stop recording under 3 seconds shows short duration alert.
    func test_tier2_feature37_stopRecordingWithDurationUnderThreeSecondsPromptsWarning() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 1.5)
        
        sut.requestStop()
        XCTAssertTrue(sut.isShowingShortRecordingAlert)
        XCTAssertEqual(sut.shortRecordingPrompt, "Recording is very short (1.5s). Save or Discard?")
    }
    
    /// Tier 2: Feature 37 - Validates stop recording while paused successfully finalizes file.
    func test_tier2_feature37_stopRecordingWhilePausedFlushesProperly() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 15.0)
        sut.pauseSession()
        
        mockAudioService.currentDuration = sut.elapsedDuration

        let url = try await sut.stopSession()
        XCTAssertEqual(sut.recordingState, .saved)
        XCTAssertEqual(url, testAudioURL)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 38: Discard Alert Cancel & State Recovery)
    
    /// Tier 2: Feature 38 - Validates dismissing discard alert resumes active recording without loss.
    func test_tier2_feature38_cancelDiscardAlertResumesRecordingCleanly() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 30.0)
        sut.requestDiscard()
        XCTAssertTrue(sut.isShowingDiscardAlert)
        
        sut.cancelDiscard()
        XCTAssertFalse(sut.isShowingDiscardAlert)
        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertEqual(sut.elapsedDuration, 30.0)
    }
    
    /// Tier 2: Feature 38 - Validates discard while paused cleans up temporary files cleanly.
    func test_tier2_feature38_discardWhilePausedCleansUpTempFiles() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.simulateTimerTick(seconds: 45.0)
        sut.pauseSession()
        
        sut.confirmDiscard()
        XCTAssertEqual(sut.recordingState, .idle)
        XCTAssertNil(fetchMeeting(id: sut.meetingId))
    }
    
    /// Tier 2: Feature 38 - Validates discard recovers gracefully even if file was already missing.
    func test_tier2_feature38_discardErrorRecoveryIfFileMissing() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        mockAudioService.simulateFileAlreadyDeleted = true

        sut.confirmDiscard()
        XCTAssertEqual(sut.recordingState, .idle)
    }

    /// A failed pause call must leave the UI recording state unchanged.
    func test_stageD_pauseFailureDoesNotOptimisticallyPauseUI() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        mockAudioService.pauseError = .invalidState("Injected pause failure")

        sut.pauseSession()

        XCTAssertEqual(sut.recordingState, .recording)
        XCTAssertEqual(mockAudioService.state, .recording)
        XCTAssertNotNil(sut.errorMessage)
    }

    /// A failed resume call must leave the UI paused.
    func test_stageD_resumeFailureDoesNotOptimisticallyResumeUI() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()
        sut.pauseSession()
        mockAudioService.resumeError = .invalidState("Injected resume failure")

        sut.resumeSession()

        XCTAssertEqual(sut.recordingState, .paused)
        XCTAssertEqual(mockAudioService.state, .paused)
        XCTAssertNotNil(sut.errorMessage)
    }

    /// Persistence retry uses the already-stopped file instead of recording a
    /// second take.
    func test_stageD_saveFailureRetainsURLAndRetrySavesWithoutRerecording() async throws {
        let saver = ControllableRecordingSaver()
        saver.error = TestPersistenceError.injected
        sut = LiveRecordingViewModel(
            meeting: initialMeeting,
            modelContext: context,
            recordingService: mockAudioService,
            transcriptionService: mockSpeechService,
            dataStore: saver,
            destinationAudioURL: testAudioURL,
            updatesFromRecordingClock: false
        )
        sut.startSession()
        try await sut.waitUntilRecordingStarted()

        do {
            _ = try await sut.finishSession()
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(sut.recordingState, .saveFailed)
            XCTAssertEqual(sut.pendingAudioURL, testAudioURL)
            XCTAssertEqual(mockAudioService.state, .stopped)
            XCTAssertTrue(FileManager.default.fileExists(atPath: testAudioURL.path))
        }

        saver.error = nil
        let recoveredURL = try sut.retrySave()
        XCTAssertEqual(recoveredURL, testAudioURL)
        XCTAssertEqual(sut.recordingState, .saved)
        XCTAssertEqual(mockAudioService.state, .stopped)
        XCTAssertEqual(saver.saveCallCount, 2)
    }

    /// Media-service reset is a deterministic interrupted state with Finish as
    /// the safe recovery when resume is unavailable.
    func test_stageD_mediaResetExposesInterruptedFinishRecovery() async throws {
        sut.startSession()
        try await sut.waitUntilRecordingStarted()

        sut.receiveInterruption(RecordingInterruptionEvent(
            code: .mediaServicesReset,
            canResume: false,
            hasEnded: true
        ))

        XCTAssertEqual(sut.recordingState, .interrupted)
        XCTAssertTrue(sut.isInterrupted)
        XCTAssertFalse(sut.interruptionCanResume)
        XCTAssertEqual(sut.recordingMetrics.interruptionCode, "mediaServicesReset")
    }

    func test_stageD_missingCanonicalFileStopsUnsavedAndPreservesRecoveryURL() async throws {
        mockAudioService.createsCanonicalFileOnStop = false
        try? FileManager.default.removeItem(at: testAudioURL)
        sut.startSession()
        try await sut.waitUntilRecordingStarted()

        do {
            _ = try await sut.finishSession()
            XCTFail("Expected canonical validation failure")
        } catch {
            XCTAssertEqual(error as? CanonicalRecordingValidationError, .fileMissing)
            XCTAssertEqual(sut.recordingState, .stoppedUnsaved)
            XCTAssertEqual(sut.pendingAudioURL, testAudioURL)
            XCTAssertEqual(mockAudioService.state, .stopped)
            XCTAssertEqual(sut.recordingMetrics.writeFailureCode, "canonical_file_missing")
        }
    }

    private enum TestPersistenceError: Error { case injected }

    @MainActor
    private final class ControllableRecordingSaver: RecordingMeetingSaving {
        var error: Error?
        var saveCallCount = 0

        func saveRecording(meeting: Meeting, audioURL: URL, duration: TimeInterval) throws {
            saveCallCount += 1
            if let error { throw error }
        }
    }
}
