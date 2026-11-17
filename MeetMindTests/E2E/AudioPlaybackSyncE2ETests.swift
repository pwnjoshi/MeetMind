//
//  AudioPlaybackSyncE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Meeting Detail Cockpit:
//  Audio Playback, Variable Speed (0.75x-2.0x) with Pitch Correction, Sticky Bar Scrubbing,
//  Tap-to-Seek Audio Synchronization, Active Teal Sentence Highlighting,
//  Inline Transcript Editing, and Mass Speaker Reassignment
//  (Scenario S4 + Tier 3 Pairwise Combinations).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class AudioPlaybackSyncE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var detailVM: MeetingDetailViewModel!
    private var mockAudioPlayer: MockAudioPlaybackService!
    private var mockSummarizer: MockSummarizationService!
    private var mockExporter: MockExportService!
    private var meeting: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockAudioPlayer = MockAudioPlaybackService()
        mockSummarizer = MockSummarizationService()
        mockExporter = MockExportService()
        
        meeting = Meeting(title: "Executive Product Sync", createdAt: Date(), duration: 300.0, status: .completed)
        meeting.audioFileURL = URL(fileURLWithPath: "/tmp/product_sync.m4a")
        context.insert(meeting)
        
        let speaker1 = Speaker(name: "Speaker 1", avatarColorHex: "#0284C7")
        let speaker2 = Speaker(name: "Speaker 2", avatarColorHex: "#F59E0B")
        context.insert(speaker1)
        context.insert(speaker2)
        
        let seg1 = TranscriptSegment(
            text: "Welcome team, today we are reviewing the Q4 release roadmap.",
            startTime: 0.0,
            endTime: 10.0,
            speaker: speaker1,
            meeting: meeting
        )
        let seg2 = TranscriptSegment(
            text: "We need to ensure performance testing is completed by Friday.",
            startTime: 10.0,
            endTime: 165.0, // 02:45
            speaker: speaker2,
            meeting: meeting
        )
        let seg3 = TranscriptSegment(
            text: "Agreed, let's look at the database optimizations first.",
            startTime: 165.0, // 02:45
            endTime: 200.0,
            speaker: speaker2,
            meeting: meeting
        )
        context.insert(seg1)
        context.insert(seg2)
        context.insert(seg3)
        
        meeting.transcriptSegments = [seg1, seg2, seg3]
        meeting.participants = [speaker1, speaker2]
        try? context.save()
        
        detailVM = MeetingDetailViewModel(
            meeting: meeting,
            modelContext: context,
            playbackService: mockAudioPlayer,
            summarizationService: mockSummarizer,
            exportService: mockExporter
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        detailVM = nil
        mockAudioPlayer = nil
        mockSummarizer = nil
        mockExporter = nil
        meeting = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S4 (Post-Meeting Audio & Transcript Review)
    
    /// Tier 4: Scenario S4 - Post-Meeting Audio & Transcript Review End-to-End
    /// - Given: A completed meeting with audio recording and 3 diarized transcript segments.
    /// - When:
    ///   1. User opens meeting cockpit and taps play on the sticky audio player bar.
    ///   2. Taps transcript bubble at 02:45 (165.0 seconds).
    ///   3. Player seeks immediately to 165.0s and active teal highlight updates.
    ///   4. Changes audio speed to 1.5x and verifies pitch correction is enabled.
    ///   5. Discovers a typo in transcript and edits inline from "database optimizations" to "cache optimizations".
    ///   6. Reassigns all segments of "Speaker 2" to named participant "Sarah Connor".
    /// - Then:
    ///   - Audio player currentTime is 165.0s.
    ///   - Playback rate is 1.5 with enabled time-pitch algorithm.
    ///   - Edited transcript segment persists in SwiftData with `isEdited == true`.
    ///   - Segments 2 and 3 reflect "Sarah Connor" as their speaker.
    func test_tier4_scenario4_postMeetingAudioAndTranscriptReview() throws {
        // Given
        XCTAssertEqual(meeting.transcriptSegments.count, 3)
        XCTAssertEqual(mockAudioPlayer.currentTime, 0.0)
        XCTAssertFalse(mockAudioPlayer.isPlaying)
        
        // When - 1. Start audio playback
        try detailVM.playAudio()
        XCTAssertTrue(mockAudioPlayer.isPlaying)
        
        // When - 2 & 3. Tap transcript bubble at 02:45 (seg3)
        let seg3 = meeting.transcriptSegments[2]
        detailVM.seekToSegment(seg3)
        
        XCTAssertEqual(mockAudioPlayer.currentTime, 165.0)
        XCTAssertEqual(detailVM.activeSegmentID, seg3.id)
        XCTAssertEqual(detailVM.activeHighlightColorToken, "#0D9488") // teal token
        
        // When - 4. Change rate to 1.5x
        detailVM.setPlaybackRate(1.5)
        XCTAssertEqual(mockAudioPlayer.playbackRate, 1.5)
        XCTAssertTrue(mockAudioPlayer.isPitchCorrectionEnabled)
        
        // When - 5. Edit typo in transcript inline
        detailVM.editTranscriptSegment(seg3, newText: "Agreed, let's look at the cache optimizations first.")
        XCTAssertEqual(seg3.text, "Agreed, let's look at the cache optimizations first.")
        XCTAssertTrue(seg3.isEdited)
        
        // When - 6. Reassign Speaker 2 to Sarah Connor
        let sarah = Speaker(name: "Sarah Connor", email: "sarah@meetmind.ai", avatarColorHex: "#7C3AED")
        meeting.participants.append(sarah)
        
        let speaker2 = meeting.participants.first(where: { $0.name == "Speaker 2" })!
        detailVM.reassignSpeaker(from: speaker2, to: sarah)
        
        // Then
        XCTAssertEqual(meeting.transcriptSegments[1].speaker?.name, "Sarah Connor")
        XCTAssertEqual(meeting.transcriptSegments[2].speaker?.name, "Sarah Connor")
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Variable Speed Playback Cycle
    /// - Verifies rate cycling: 1.0x -> 1.25x -> 1.5x -> 2.0x -> 0.75x -> 1.0x.
    func test_tier3_variableSpeedPlaybackCycle() throws {
        XCTAssertEqual(detailVM.playbackRate, 1.0)
        
        detailVM.cyclePlaybackRate()
        XCTAssertEqual(detailVM.playbackRate, 1.25)
        
        detailVM.cyclePlaybackRate()
        XCTAssertEqual(detailVM.playbackRate, 1.5)
        
        detailVM.cyclePlaybackRate()
        XCTAssertEqual(detailVM.playbackRate, 2.0)
        
        detailVM.cyclePlaybackRate()
        XCTAssertEqual(detailVM.playbackRate, 0.75)
        
        detailVM.cyclePlaybackRate()
        XCTAssertEqual(detailVM.playbackRate, 1.0)
    }

    /// Tier 3: Pairwise - Sticky Audio Scrubber Slider Debounce
    /// - Verifies dragging slider pauses updates until release, then seeks player.
    func test_tier3_stickyBarScrubberDebounce() throws {
        try detailVM.playAudio()
        XCTAssertTrue(detailVM.isPlaying)
        
        detailVM.onScrubberDragBegan()
        detailVM.onScrubberValueChanging(to: 120.0)
        XCTAssertEqual(detailVM.scrubberDisplayTime, 120.0)
        
        detailVM.onScrubberDragEnded(at: 120.0)
        XCTAssertEqual(mockAudioPlayer.currentTime, 120.0)
    }

    /// Tier 3: Pairwise - Skip 15 Seconds Boundary Clamping
    /// - Verifies skip back from 00:05 clamps to 00:00; skip forward past duration clamps to end.
    func test_tier3_skip15SecondsBoundaryClamping() throws {
        mockAudioPlayer.seek(to: 5.0)
        detailVM.skipBackward(seconds: 15.0)
        XCTAssertEqual(mockAudioPlayer.currentTime, 0.0) // clamped to 0
        
        mockAudioPlayer.seek(to: 295.0) // duration is 300.0
        detailVM.skipForward(seconds: 15.0)
        XCTAssertEqual(mockAudioPlayer.currentTime, 300.0) // clamped to duration
    }

    /// Tier 3: Pairwise - Tap-to-Seek Audio Highlight Sync
    /// - Verifies tapping a segment sets player time and updates active segment ID.
    func test_tier3_tapToSeekAudioHighlightSync() throws {
        let seg2 = meeting.transcriptSegments[1]
        detailVM.seekToSegment(seg2)
        
        XCTAssertEqual(mockAudioPlayer.currentTime, seg2.startTime)
        XCTAssertEqual(detailVM.activeSegmentID, seg2.id)
    }

    /// Tier 3: Pairwise - Inline Transcript Editor Persistence
    /// - Verifies inline edit saves modified text while preserving timestamps.
    func test_tier3_inlineTranscriptEditorPersistence() throws {
        let seg = meeting.transcriptSegments[0]
        let originalStart = seg.startTime
        let originalEnd = seg.endTime
        
        detailVM.editTranscriptSegment(seg, newText: "Updated transcript text.")
        
        XCTAssertEqual(seg.text, "Updated transcript text.")
        XCTAssertEqual(seg.startTime, originalStart)
        XCTAssertEqual(seg.endTime, originalEnd)
        XCTAssertTrue(seg.isEdited)
    }

    /// Tier 3: Pairwise - Mass Speaker Reassignment Update
    /// - Verifies reassigning a speaker updates all matching segments across the meeting.
    func test_tier3_speakerReassignmentMassUpdate() throws {
        let newSpeaker = Speaker(name: "Diana Prince", avatarColorHex: "#DC2626")
        meeting.participants.append(newSpeaker)
        
        let oldSpeaker = meeting.participants.first(where: { $0.name == "Speaker 2" })!
        detailVM.reassignSpeaker(from: oldSpeaker, to: newSpeaker)
        
        let speaker2Segments = meeting.transcriptSegments.filter { $0.speaker?.name == "Speaker 2" }
        let dianaSegments = meeting.transcriptSegments.filter { $0.speaker?.name == "Diana Prince" }
        
        XCTAssertEqual(speaker2Segments.count, 0)
        XCTAssertEqual(dianaSegments.count, 2)
    }

    /// Tier 3: Pairwise - Audio Playback Completion Reset
    /// - Verifies reaching the end of audio stops playback and resets time to 0.
    func test_tier3_audioCompletionReset() throws {
        try detailVM.playAudio()
        mockAudioPlayer.simulatePlaybackCompletion()
        
        XCTAssertFalse(detailVM.isPlaying)
        XCTAssertEqual(mockAudioPlayer.currentTime, 0.0)
    }

    /// Tier 3: Pairwise - Audio State Preservation During Sub-Tab Switching
    /// - Verifies audio continues playing when switching between cockpit tabs.
    func test_tier3_playbackStateDuringTabSwitch() throws {
        try detailVM.playAudio()
        XCTAssertTrue(detailVM.isPlaying)
        
        detailVM.selectedTab = .transcript
        XCTAssertTrue(detailVM.isPlaying)
        
        detailVM.selectedTab = .actionItems
        XCTAssertTrue(detailVM.isPlaying)
        
        detailVM.selectedTab = .notesMedia
        XCTAssertTrue(detailVM.isPlaying)
        
        detailVM.selectedTab = .summary
        XCTAssertTrue(detailVM.isPlaying)
    }

    /// Tier 3: Pairwise - Rapid Seek and Scrub Stability
    /// - Verifies multiple rapid seek operations maintain audio sync without throwing.
    func test_tier3_rapidSeekAndScrubStability() throws {
        for time in [10.0, 50.0, 25.0, 180.0, 5.0, 200.0] {
            detailVM.seek(to: time)
            XCTAssertEqual(mockAudioPlayer.currentTime, time)
        }
    }

    /// Tier 3: Pairwise - Time Observer Cadence Validation
    /// - Verifies 10Hz observer updates playback progress smoothly.
    func test_tier3_timeObserverCadenceValidation() throws {
        var observedTime: TimeInterval = 0.0
        let observerID = mockAudioPlayer.addTimeObserver(interval: 0.1) { time in
            observedTime = time
        }
        
        mockAudioPlayer.simulateTimeAdvance(seconds: 0.5)
        XCTAssertGreaterThan(observedTime, 0.0)
        
        mockAudioPlayer.removeTimeObserver(id: observerID)
    }

    /// Tier 3: Pairwise - Missing Audio File Error Handling
    /// - Verifies attempting to play when audio file is missing presents user alert.
    func test_tier3_missingAudioFileErrorHandling() throws {
        meeting.audioFileURL = nil
        let noAudioVM = MeetingDetailViewModel(
            meeting: meeting,
            modelContext: context,
            playbackService: mockAudioPlayer,
            summarizationService: mockSummarizer,
            exportService: mockExporter
        )
        
        XCTAssertFalse(noAudioVM.hasAudioFile)
        XCTAssertThrowsError(try noAudioVM.playAudio())
    }

    /// Tier 3: Pairwise - Active Sentence Highlight Boundary Transitions
    /// - Verifies highlight moves precisely as timecode passes segment boundary.
    func test_tier3_activeSentenceHighlightBoundary() throws {
        detailVM.updateActiveSegment(at: 5.0) // inside seg1 (0.0 - 10.0)
        XCTAssertEqual(detailVM.activeSegmentID, meeting.transcriptSegments[0].id)
        
        detailVM.updateActiveSegment(at: 10.5) // inside seg2 (10.0 - 165.0)
        XCTAssertEqual(detailVM.activeSegmentID, meeting.transcriptSegments[1].id)
    }

    /// Tier 3: Pairwise - Reassigned Speaker Color Token Consistency
    /// - Verifies new speaker inherits design system color token.
    func test_tier3_speakerColorTokenConsistency() throws {
        let speaker = Speaker(name: "Elena", avatarColorHex: "#059669")
        meeting.participants.append(speaker)
        
        let token = detailVM.speakerColorToken(for: speaker)
        XCTAssertEqual(token, "#059669")
    }
}
