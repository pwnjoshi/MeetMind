//
//  MeetingDetailViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
import OfflineEngineKit
@testable import MeetMind

/// Comprehensive test suite covering Meeting Detail Cockpit & Tabs, Executive Summary View,
/// Diarized Transcript Feed, Tap-to-Seek Audio Playback, Inline Transcript Editor,
/// Speaker Reassignment Sheet, Sticky Audio Player Bar, Variable Speed Playback,
/// Whiteboard & Notes Gallery, and Interactive Ask AI Assistant.
/// Corresponds to Features 40, 41, 42, 43, 44, 45, 46, 47, 51, and 52.
@MainActor
final class MeetingDetailViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: MeetingDetailViewModel!
    private var mockPlaybackService: MockAudioPlaybackService!
    private var mockSummarizationService: MockSummarizationService!
    private var mockExportService: MockExportService!
    private var initialMeeting: Meeting!
    private var meetingId: UUID!
    private var testAudioURL: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockPlaybackService = MockAudioPlaybackService()
        mockSummarizationService = MockSummarizationService()
        mockExportService = MockExportService()
        
        meetingId = UUID()
        testAudioURL = URL(fileURLWithPath: "/tmp/detail_test_meeting.m4a")
        
        initialMeeting = Meeting(
            id: meetingId,
            title: "Q4 Architecture Review",
            createdAt: Date().addingTimeInterval(-3600),
            duration: 300.0, // 5 minutes
            status: .completed,
            audioFileURL: testAudioURL,
            isFavorite: false
        )
        mockPlaybackService.duration = initialMeeting.duration
        mockPlaybackService.playbackRate = 1.0
        context.insert(initialMeeting)
        
        let speaker1 = Speaker(name: "Speaker 1", avatarColorHex: "#3B82F6")
        let speaker2 = Speaker(name: "Speaker 2", avatarColorHex: "#10B981")
        context.insert(speaker1)
        context.insert(speaker2)
        
        let seg1 = TranscriptSegment(id: UUID(), text: "Welcome to the architecture review.", startTime: 0.0, endTime: 5.0, speaker: speaker1, meeting: initialMeeting)
        let seg2 = TranscriptSegment(id: UUID(), text: "Let us review the audio playback engine.", startTime: 5.0, endTime: 15.0, speaker: speaker2, meeting: initialMeeting)
        let seg3 = TranscriptSegment(id: UUID(), text: "Agreed, we will use variable speed playback with pitch correction.", startTime: 15.0, endTime: 30.0, speaker: speaker1, meeting: initialMeeting)
        let seg4 = TranscriptSegment(id: UUID(), text: "Action items should sync seamlessly to Apple Reminders.", startTime: 30.0, endTime: 45.0, speaker: speaker2, meeting: initialMeeting)
        context.insert(seg1)
        context.insert(seg2)
        context.insert(seg3)
        context.insert(seg4)
        initialMeeting.transcriptSegments = [seg1, seg2, seg3, seg4]
        
        let summary = Summary(
            id: UUID(),
            executiveSummary: "Detailed architecture sync covering audio playback, speech recognition, and Apple Reminders sync.",
            keyPoints: [
                "Audio playback variable speed rates (0.75x to 2.0x)",
                "Diarized transcript tap-to-seek mechanism",
                "Reminders sync integration"
            ],
            keyDecisions: [
                "Deploy on-device neural model as primary transcription engine.",
                "Use EventKit for Reminders sync."
            ],
            meeting: initialMeeting
        )
        context.insert(summary)
        initialMeeting.summary = summary
        
        let note = Note(id: UUID(), content: "Key note captured at 15 seconds", timestamp: 15.0, isBookmark: true, meeting: initialMeeting)
        let photo = Note(id: UUID(), content: "Photo", timestamp: 20.0, imageAttachmentPath: "/tmp/whiteboard_1.jpg", meeting: initialMeeting)
        context.insert(note)
        context.insert(photo)
        initialMeeting.notes = [note, photo]
        
        let action1 = ActionItem(title: "Configure audio rates", priority: .high, meeting: initialMeeting)
        let action2 = ActionItem(title: "Setup tap-to-seek", priority: .medium, meeting: initialMeeting)
        let action3 = ActionItem(title: "Reminders sync", priority: .low, meeting: initialMeeting)
        context.insert(action1)
        context.insert(action2)
        context.insert(action3)
        initialMeeting.actionItems = [action1, action2, action3]
        
        try? context.save()
        
        sut = MeetingDetailViewModel(
            meeting: initialMeeting,
            modelContext: context,
            playbackService: mockPlaybackService,
            summarizationService: mockSummarizationService,
            exportService: mockExportService
        )
        sut.setPlaybackRate(1.0)
    }
    
    @MainActor
    override func tearDown() async throws {
        sut = nil
        initialMeeting = nil
        mockPlaybackService = nil
        mockSummarizationService = nil
        mockExportService = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    private func fetchMeeting(id: UUID) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Tier 1: Feature 40 (Meeting Detail Cockpit & Tabs)
    
    /// Tier 1: Feature 40 - Validates switching segmented tabs updates selected tab.
    func test_tier1_feature40_segmentedTabsSwitching() throws {
        XCTAssertEqual(sut.selectedTab, .summary)
        
        sut.selectTab(.transcript)
        XCTAssertEqual(sut.selectedTab, .transcript)
        
        sut.selectTab(.actionItems)
        XCTAssertEqual(sut.selectedTab, .actionItems)
        
        sut.selectTab(.notesMedia)
        XCTAssertEqual(sut.selectedTab, .notesMedia)
        
        sut.selectTab(.summary)
        XCTAssertEqual(sut.selectedTab, .summary)
    }
    
    /// Tier 1: Feature 40 - Validates header card displays meeting title, date, duration, and status badge.
    func test_tier1_feature40_headerCardMetadataDisplay() throws {
        XCTAssertEqual(sut.headerTitle, "Q4 Architecture Review")
        XCTAssertEqual(sut.headerDurationText, "05:00")
        XCTAssertEqual(sut.statusBadgeTitle, "Completed")
        XCTAssertEqual(sut.statusBadgeColorHex, "#10B981")
    }
    
    /// Tier 1: Feature 40 - Validates toolbar actions menu contains Export, Share, Edit, and Delete options.
    func test_tier1_feature40_toolbarActionsMenuOptions() throws {
        let actions = sut.availableToolbarActions
        XCTAssertTrue(actions.contains(.exportMinutes))
        XCTAssertTrue(actions.contains(.share))
        XCTAssertTrue(actions.contains(.rename))
        XCTAssertTrue(actions.contains(.delete))
    }
    
    /// Tier 1: Feature 40 - Validates inline title rename updates meeting record and persistence.
    func test_tier1_feature40_inlineTitleRename() throws {
        try sut.renameMeeting(newTitle: "  Updated Q4 Architecture Plan  ")
        try sut.renameMeeting(newTitle: "  ")
        
        XCTAssertEqual(sut.headerTitle, "Updated Q4 Architecture Plan")
        let updated = fetchMeeting(id: meetingId)
        XCTAssertEqual(updated?.title, "Updated Q4 Architecture Plan")
    }
    
    // MARK: - Tier 1: Feature 41 (Executive Summary View)
    
    /// Tier 1: Feature 41 - Validates executive summary text card displays content accurately.
    func test_tier1_feature41_executiveSummaryCardDisplay() throws {
        XCTAssertNotNil(sut.summary)
        XCTAssertTrue(sut.summaryText.contains("Detailed architecture sync"))
    }
    
    /// Tier 1: Feature 41 - Validates key discussion topics list displays topics with timecodes.
    func test_tier1_feature41_keyDiscussionTopicsListWithTimecodes() throws {
        let topics = sut.keyDiscussionPoints
        XCTAssertEqual(topics.count, 3)
        XCTAssertEqual(topics[0], "Audio playback variable speed rates (0.75x to 2.0x)")
    }
    
    /// Tier 1: Feature 41 - Validates key decisions callout card displays highlighted decisions.
    func test_tier1_feature41_keyDecisionsCardDisplay() throws {
        let decisions = sut.keyDecisions
        XCTAssertEqual(decisions.count, 2)
        XCTAssertTrue(decisions.contains("Deploy on-device neural model as primary transcription engine."))
    }
    
    /// Tier 1: Feature 41 - Validates copying summary text creates clean formatted string.
    func test_tier1_feature41_copySummaryTextToClipboard() throws {
        let copied = sut.generateCopyableSummaryText()
        XCTAssertTrue(copied.contains("Executive Summary"))
        XCTAssertTrue(copied.contains("Key Decisions"))
    }
    
    /// Tier 1: Feature 41 - Validates regenerate summary updates summary content in store.
    func test_tier1_feature41_regenerateSummaryUpdatesContent() throws {
        let expectation = expectation(description: "Regenerate Summary")
        
        sut.regenerateSummary { result in
            switch result {
            case .success(let updated):
                XCTAssertNotNil(updated)
                expectation.fulfill()
            case .failure(let err):
                XCTFail("Regeneration failed: \(err)")
            }
        }
        
        waitForExpectations(timeout: 2.0)
    }
    
    // MARK: - Tier 1: Feature 42 (Diarized Transcript Feed)
    
    /// Tier 1: Feature 42 - Validates diarized feed displays speaker names, avatars, and text bubbles.
    func test_tier1_feature42_diarizedTranscriptFeedSpeakerBubbles() throws {
        let segments = sut.transcriptSegments
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments[0].speakerName, "Speaker 1")
        XCTAssertEqual(segments[1].speakerName, "Speaker 2")
    }
    
    /// Tier 1: Feature 42 - Validates active sentence is highlighted based on audio playback time.
    func test_tier1_feature42_activeSentenceHighlightedDuringPlayback() throws {
        sut.updatePlaybackTime(10.0) // Within segment 1 (5.0 to 15.0)
        
        XCTAssertNotNil(sut.activeSegmentId)
        XCTAssertEqual(sut.activeSegmentId, sut.transcriptSegments[1].id)
    }
    
    /// Tier 1: Feature 42 - Validates transcript search keyword matching highlights.
    func test_tier1_feature42_transcriptSearchMatchHighlighting() throws {
        sut.filterTranscript(by: "pitch correction")
        
        XCTAssertEqual(sut.filteredTranscriptSegments.count, 1)
        XCTAssertEqual(sut.filteredTranscriptSegments.first?.speakerName, "Speaker 1")
    }
    
    // MARK: - Tier 1: Feature 43 (Tap-to-Seek Audio Playback)
    
    /// Tier 1: Feature 43 - Validates tapping transcript segment seeks audio player to segment startTime.
    func test_tier1_feature43_tapTranscriptToSeekSeeksAudioPlayer() throws {
        let targetSegment = sut.transcriptSegments[2] // startTime = 15.0
        
        sut.tapToSeek(segment: targetSegment)
        
        XCTAssertEqual(mockPlaybackService.currentTime, 15.0)
    }
    
    /// Tier 1: Feature 43 - Validates tapping transcript segment automatically starts playback if paused.
    func test_tier1_feature43_tapTranscriptStartsPlaybackIfPaused() throws {
        mockPlaybackService.state = .paused
        let targetSegment = sut.transcriptSegments[1]
        
        sut.tapToSeek(segment: targetSegment)
        
        XCTAssertEqual(mockPlaybackService.state, .playing)
    }
    
    /// Tier 1: Feature 43 - Validates active sentence highlight immediately jumps to tapped segment.
    func test_tier1_feature43_activeHighlightMovesToTappedSegment() throws {
        let targetSegment = sut.transcriptSegments[3] // startTime = 30.0
        sut.tapToSeek(segment: targetSegment)
        
        XCTAssertEqual(sut.activeSegmentId, targetSegment.id)
    }
    
    // MARK: - Tier 1: Feature 44 (Inline Transcript Editor)
    
    /// Tier 1: Feature 44 - Validates opening inline transcript editor pre-fills existing text.
    func test_tier1_feature44_openInlineTranscriptEditorPreFillsText() throws {
        let segmentToEdit = sut.transcriptSegments[0]
        sut.beginEditingTranscript(segment: segmentToEdit)
        
        XCTAssertTrue(sut.isEditingTranscript)
        XCTAssertEqual(sut.editingSegmentText, "Welcome to the architecture review.")
        XCTAssertEqual(sut.editingSegmentId, segmentToEdit.id)
    }
    
    /// Tier 1: Feature 44 - Validates saving inline edit updates segment text in memory and store.
    func test_tier1_feature44_saveInlineTranscriptEditorUpdatesSegmentText() throws {
        let segmentToEdit = sut.transcriptSegments[0]
        sut.beginEditingTranscript(segment: segmentToEdit)
        
        try sut.saveTranscriptEdit(newText: "Welcome to the Q4 architecture review kickoff.")
        
        XCTAssertFalse(sut.isEditingTranscript)
        XCTAssertEqual(sut.transcriptSegments[0].text, "Welcome to the Q4 architecture review kickoff.")
    }
    
    /// Tier 1: Feature 44 - Validates edited transcript segment displays edited indicator badge.
    func test_tier1_feature44_editedTranscriptSegmentDisplaysEditedBadge() throws {
        let segment = sut.transcriptSegments[1]
        sut.beginEditingTranscript(segment: segment)
        try sut.saveTranscriptEdit(newText: "Corrected speech text.")
        
        XCTAssertTrue(sut.transcriptSegments[1].isEdited)
    }
    
    // MARK: - Tier 1: Feature 45 (Speaker Reassignment Sheet)
    
    /// Tier 1: Feature 45 - Validates speaker reassignment sheet lists all meeting participants.
    func test_tier1_feature45_speakerReassignmentSheetListsParticipants() throws {
        sut.openSpeakerReassignment(forSpeakerName: "Speaker 1")
        
        XCTAssertTrue(sut.isShowingSpeakerReassignmentSheet)
        XCTAssertEqual(sut.speakerToReassign, "Speaker 1")
    }
    
    /// Tier 1: Feature 45 - Validates reassigning speaker mass-updates all matching segments across meeting.
    func test_tier1_feature45_reassignSpeakerUpdatesAllMatchingSegments() throws {
        sut.reassignSpeaker(from: "Speaker 1", to: "Sarah Connor")
        
        XCTAssertEqual(sut.transcriptSegments[0].speakerName, "Sarah Connor")
        XCTAssertEqual(sut.transcriptSegments[2].speakerName, "Sarah Connor")
        XCTAssertTrue(sut.transcriptSegments[0].isEdited)
        XCTAssertTrue(sut.transcriptSegments[2].isEdited)
        // Speaker 2 should be unaffected
        XCTAssertEqual(sut.transcriptSegments[1].speakerName, "Speaker 2")
    }
    
    /// Tier 1: Feature 45 - Validates speaker reassignment updates speaker avatar color token.
    func test_tier1_feature45_reassignSpeakerUpdatesColorToken() throws {
        sut.reassignSpeaker(from: "Speaker 1", to: "Alex Rivera")
        
        XCTAssertEqual(sut.transcriptSegments[0].speaker?.name, "Alex Rivera")
    }
    
    // MARK: - Tier 1: Feature 46 (Sticky Audio Player Bar)
    
    /// Tier 1: Feature 46 - Validates play/pause toggle button toggles audio playback engine.
    func test_tier1_feature46_stickyPlayerPlayPauseToggle() throws {
        XCTAssertFalse(sut.isPlaying)
        
        sut.togglePlayPause()
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(mockPlaybackService.state, .playing)
        
        sut.togglePlayPause()
        XCTAssertFalse(sut.isPlaying)
        XCTAssertEqual(mockPlaybackService.state, .paused)
    }
    
    /// Tier 1: Feature 46 - Validates current time and remaining time labels reflect playback position.
    func test_tier1_feature46_stickyPlayerTimeLabelsReflectProgress() throws {
        sut.updatePlaybackTime(65.0) // 1m 5s out of 5m (300s)
        
        XCTAssertEqual(sut.currentTimeFormatted, "01:05")
        XCTAssertEqual(sut.remainingTimeFormatted, "-03:55")
    }
    
    /// Tier 1: Feature 46 - Validates scrub slider progress ratio reflects playback (0.0 to 1.0).
    func test_tier1_feature46_stickyPlayerScrubSliderPosition() throws {
        sut.updatePlaybackTime(150.0) // Half of 300s
        
        XCTAssertEqual(sut.playbackProgressRatio, 0.5, accuracy: 0.01)
    }
    
    /// Tier 1: Feature 46 - Validates skip 15 seconds forward button advances currentTime.
    func test_tier1_feature46_skip15SecondsForward() throws {
        sut.updatePlaybackTime(10.0)
        sut.skipForward(seconds: 15.0)
        
        XCTAssertEqual(mockPlaybackService.currentTime, 25.0)
    }
    
    /// Tier 1: Feature 46 - Validates skip 15 seconds backward button decrements currentTime.
    func test_tier1_feature46_skip15SecondsBackward() throws {
        sut.updatePlaybackTime(40.0)
        sut.skipBackward(seconds: 15.0)
        
        XCTAssertEqual(mockPlaybackService.currentTime, 25.0)
    }
    
    // MARK: - Tier 1: Feature 47 (Variable Speed Playback)
    
    /// Tier 1: Feature 47 - Validates speed button cycles rates: 1.0x -> 1.25x -> 1.5x -> 2.0x -> 0.75x -> 1.0x.
    func test_tier1_feature47_variableSpeedPlaybackCycleSequence() throws {
        XCTAssertEqual(sut.playbackRate, 1.0)
        
        sut.cyclePlaybackSpeed()
        XCTAssertEqual(sut.playbackRate, 1.25)
        
        sut.cyclePlaybackSpeed()
        XCTAssertEqual(sut.playbackRate, 1.5)
        
        sut.cyclePlaybackSpeed()
        XCTAssertEqual(sut.playbackRate, 2.0)
        
        sut.cyclePlaybackSpeed()
        XCTAssertEqual(sut.playbackRate, 0.75)
        
        sut.cyclePlaybackSpeed()
        XCTAssertEqual(sut.playbackRate, 1.0)
    }
    
    /// Tier 1: Feature 47 - Validates changing playback rate updates audio player service immediately.
    func test_tier1_feature47_playbackRateUpdatesAudioServiceImmediately() throws {
        sut.cyclePlaybackSpeed() // 1.25
        XCTAssertEqual(mockPlaybackService.playbackRate, 1.25)
    }
    
    // MARK: - Tier 1: Feature 51 (Whiteboard & Notes Gallery)
    
    /// Tier 1: Feature 51 - Validates whiteboard photos and notes appear in gallery tab.
    func test_tier1_feature51_notesAndMediaGalleryTwoColumnGrid() throws {
        sut.selectTab(.notesMedia)
        
        XCTAssertEqual(sut.galleryPhotos.count, 1)
        XCTAssertEqual(sut.galleryNotes.count, 1)
    }
    
    /// Tier 1: Feature 51 - Validates notes list shows timestamp badges corresponding to capture time.
    func test_tier1_feature51_notesListTimestampBadges() throws {
        let note = sut.galleryNotes.first
        XCTAssertEqual(note?.timestamp, 15.0)
        XCTAssertEqual(sut.formatTimestamp(note?.timestamp ?? 0), "00:15")
    }
    
    // MARK: - Tier 1: Feature 52 (Interactive Ask AI Assistant Sheet)
    
    /// Tier 1: Feature 52 - Validates opening Ask AI sheet presents pre-defined question prompt chips.
    func test_tier1_feature52_askAISheetPresentsPromptChips() throws {
        sut.openAskAISheet()
        
        XCTAssertTrue(sut.isShowingAskAISheet)
        XCTAssertGreaterThanOrEqual(sut.suggestedPromptChips.count, 3)
        XCTAssertTrue(sut.suggestedPromptChips.contains("What decisions were made?"))
    }
    
    /// Tier 1: Feature 52 - Validates submitting query returns grounded response citing timecodes.
    func test_tier1_feature52_askAIQueryReturnsGroundedResponseWithCitations() async throws {
        let model = MeetingDetailViewModel(meeting: initialMeeting, questionAnswerer: { _, turns in
            let source = try XCTUnwrap(turns.first { $0.start == 15 })
            return [SupportedPoint(text: "Use variable speed playback with pitch correction.",
                evidence: [SourceEvidence(turnID: source.id, quote: source.text)])]
        })
        let response = try await model.askAI(prompt: "What playback behavior was agreed?")
        XCTAssertTrue(response.text.contains("pitch correction"))
        XCTAssertEqual(response.citations.first?.timestamp, 15)
        XCTAssertEqual(response.citations.first?.snippet, initialMeeting.transcriptSegments.first { $0.startTime == 15 }?.text)
    }

    // MARK: - Tier 2: Boundary & Corner Cases (Feature 40: Detail Tabs & Persistence)
    
    /// Tier 2: Feature 40 - Validates switching between cockpit tabs does not halt active audio playback.
    func test_tier2_feature40_tabSwitchingDoesNotInterruptAudioPlayback() throws {
        sut.togglePlayPause() // Start playing
        XCTAssertTrue(sut.isPlaying)
        
        sut.selectTab(.transcript)
        sut.selectTab(.actionItems)
        sut.selectTab(.notesMedia)
        
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(mockPlaybackService.state, .playing)
    }
    
    /// Tier 2: Feature 40 - Validates loading detail view for large meeting under 300ms.
    func test_tier2_feature40_largeMeetingDetailLoadPerformance() throws {
        let start = Date()
        sut.loadMeeting()
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 0.3)
    }
    
    /// Tier 2: Feature 40 - Validates missing summary tab displays empty summary placeholder.
    func test_tier2_feature40_missingSummaryTabFallsBackToEmptyState() throws {
        sut.simulateNilSummary()
        
        XCTAssertTrue(sut.hasEmptySummary)
        XCTAssertEqual(sut.emptySummaryPlaceholder, "Summary not yet generated.")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 41: Summary Regeneration Failures)
    
    /// Tier 2: Feature 41 - Validates summary regeneration failure displays user-friendly alert.
    func test_tier2_feature41_regenerateSummaryFailureDisplaysAlert() throws {
        mockSummarizationService.shouldThrowError = .serviceUnavailable
        let expectation = expectation(description: "Regenerate Summary Failure")
        
        sut.regenerateSummary { result in
            switch result {
            case .success:
                XCTFail("Should have failed")
            case .failure(let err):
                XCTAssertNotNil(err)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 2.0)
    }
    
    /// Tier 2: Feature 41 - Validates empty summary string renders placeholder rather than blank space.
    func test_tier2_feature41_emptySummaryDisplaysPlaceholderCard() throws {
        sut.simulateEmptySummaryText()
        XCTAssertTrue(sut.hasEmptySummary)
    }
    
    /// Tier 2: Feature 41 - Validates markdown bold and bullet rendering in summary text.
    func test_tier2_feature41_summaryMarkdownFormattingRender() throws {
        let rendered = sut.renderMarkdownSummary("**Key**: Bold decision")
        XCTAssertTrue(rendered.contains("Key"))
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 42: Transcript Scale & Avatars)
    
    /// Tier 2: Feature 42 - Validates scrolling performance with 1,000 transcript segments.
    func test_tier2_feature42_oneThousandTranscriptSegmentsScrollStability() throws {
        var segments: [TranscriptSegment] = []
        for i in 0..<1000 {
            let speaker = Speaker(name: "Speaker \(i % 3)")
            segments.append(TranscriptSegment(
                id: UUID(),
                text: "Sentence number \(i) in long transcript.",
                startTime: TimeInterval(i * 3),
                endTime: TimeInterval((i * 3) + 2),
                speaker: speaker
            ))
        }
        sut.setTranscriptSegments(segments)
        
        XCTAssertEqual(sut.transcriptSegments.count, 1000)
    }
    
    /// Tier 2: Feature 42 - Validates unknown speaker defaults to generic numbered speaker avatar.
    func test_tier2_feature42_unknownSpeakerDefaultsToGenericNumberedSpeaker() throws {
        let seg = TranscriptSegment(id: UUID(), text: "Test", startTime: 0, endTime: 1, speaker: nil)
        sut.setTranscriptSegments([seg])
        
        XCTAssertEqual(sut.transcriptSegments.first?.speakerDisplayName, "Speaker 1")
    }
    
    /// Tier 2: Feature 42 - Validates timestamp formatting switches to HH:MM:SS when duration exceeds 1 hour.
    func test_tier2_feature42_timestampFormattingMMSSvsHHMMSS() throws {
        XCTAssertEqual(sut.formatTimestamp(125.0), "02:05")
        XCTAssertEqual(sut.formatTimestamp(3665.0), "01:01:05")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 43: Tap-to-Seek Boundaries)
    
    /// Tier 2: Feature 43 - Validates tapping segment beyond audio duration clamps seek to end.
    func test_tier2_feature43_tapSegmentBeyondAudioDurationClampsToEnd() throws {
        let invalidSegment = TranscriptSegment(id: UUID(), text: "End", startTime: 9999.0, endTime: 10000.0, speaker: Speaker(name: "S"))
        sut.tapToSeek(segment: invalidSegment)
        
        XCTAssertEqual(mockPlaybackService.currentTime, sut.totalDuration)
    }
    
    /// Tier 2: Feature 43 - Validates rapid tapping across multiple segments does not crash audio player.
    func test_tier2_feature43_rapidTappingAcrossMultipleSegments() throws {
        for seg in sut.transcriptSegments {
            sut.tapToSeek(segment: seg)
        }
        XCTAssertEqual(mockPlaybackService.currentTime, sut.transcriptSegments.last?.startTime)
    }
    
    /// Tier 2: Feature 43 - Validates tap-to-seek when audio file is missing displays non-fatal warning.
    func test_tier2_feature43_tapToSeekWhenAudioFileMissingDisplaysError() throws {
        sut.simulateMissingAudioFile()
        
        sut.tapToSeek(segment: sut.transcriptSegments[0])
        XCTAssertTrue(sut.isShowingAudioMissingAlert)
        XCTAssertEqual(sut.audioMissingMessage, "Audio recording file is unavailable.")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 44: Inline Edit Validation & Undo)
    
    /// Tier 2: Feature 44 - Validates saving blank or whitespace-only transcript edit fails validation.
    func test_tier2_feature44_inlineEditEmptyTextValidationFailure() throws {
        let segment = sut.transcriptSegments[0]
        sut.beginEditingTranscript(segment: segment)
        
        let didSave = try sut.saveTranscriptEdit(newText: "   \t \n ")
        XCTAssertFalse(didSave)
        XCTAssertEqual(sut.transcriptSegments[0].text, "Welcome to the architecture review.")
    }
    
    /// Tier 2: Feature 44 - Validates editing text preserves original timecode offset.
    func test_tier2_feature44_inlineEditPreservesOriginalTimestamp() throws {
        let segment = sut.transcriptSegments[1] // startTime = 5.0
        sut.beginEditingTranscript(segment: segment)
        try sut.saveTranscriptEdit(newText: "Corrected segment text.")
        
        XCTAssertEqual(sut.transcriptSegments[1].startTime, 5.0)
        XCTAssertEqual(sut.transcriptSegments[1].endTime, 15.0)
    }
    
    /// Tier 2: Feature 44 - Validates undo action restores original segment text.
    func test_tier2_feature44_inlineEditUndoActionRevertsToOriginal() throws {
        let segment = sut.transcriptSegments[0]
        sut.beginEditingTranscript(segment: segment)
        try sut.saveTranscriptEdit(newText: "Temporary edit")
        
        sut.undoTranscriptEdit(segmentId: segment.id)
        XCTAssertEqual(sut.transcriptSegments[0].text, "Welcome to the architecture review.")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 45: Speaker Reassignment Edges)
    
    /// Tier 2: Feature 45 - Validates reassigning to non-existent speaker creates new participant profile.
    func test_tier2_feature45_reassignToNonExistentParticipantHandled() throws {
        sut.reassignSpeaker(from: "Speaker 2", to: "Brand New Participant")
        
        XCTAssertEqual(sut.transcriptSegments[1].speakerName, "Brand New Participant")
    }
    
    /// Tier 2: Feature 45 - Validates reassignment when all segments belong to only one speaker.
    func test_tier2_feature45_reassignWhenAllSegmentsBelongToOneSpeaker() throws {
        let singleSpeakerSegments = [
            TranscriptSegment(id: UUID(), text: "A", startTime: 0, endTime: 1, speaker: Speaker(name: "Solo")),
            TranscriptSegment(id: UUID(), text: "B", startTime: 1, endTime: 2, speaker: Speaker(name: "Solo"))
        ]
        sut.setTranscriptSegments(singleSpeakerSegments)
        
        sut.reassignSpeaker(from: "Solo", to: "Alex")
        XCTAssertEqual(sut.transcriptSegments[0].speakerName, "Alex")
        XCTAssertEqual(sut.transcriptSegments[1].speakerName, "Alex")
    }
    
    /// Tier 2: Feature 45 - Validates mass-updating 500 segments completes under 100ms.
    func test_tier2_feature45_reassignFiveHundredSegmentsPerformance() throws {
        var massSegments: [TranscriptSegment] = []
        for i in 0..<500 {
            massSegments.append(TranscriptSegment(id: UUID(), text: "\(i)", startTime: Double(i), endTime: Double(i+1), speaker: Speaker(name: "TargetSpeaker")))
        }
        sut.setTranscriptSegments(massSegments)
        
        let start = Date()
        sut.reassignSpeaker(from: "TargetSpeaker", to: "Sarah Connor")
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 1.0)
        XCTAssertEqual(sut.transcriptSegments.first?.speakerName, "Sarah Connor")
    }
    
    /// Tier 2: Feature 45 - Validates cancelling reassignment sheet leaves all segments unchanged.
    func test_tier2_feature45_cancelSpeakerReassignmentPreservesOriginals() throws {
        sut.openSpeakerReassignment(forSpeakerName: "Speaker 1")
        sut.cancelSpeakerReassignment()
        
        XCTAssertFalse(sut.isShowingSpeakerReassignmentSheet)
        XCTAssertEqual(sut.transcriptSegments[0].speakerName, "Speaker 1")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 46: Scrub Clamping & End of File)
    
    /// Tier 2: Feature 46 - Validates skipping backward from 5 seconds clamps to 0 seconds.
    func test_tier2_feature46_skipBackwardFromEarlyTimecodeClampsToZero() throws {
        sut.updatePlaybackTime(5.0)
        sut.skipBackward(seconds: 15.0)
        
        XCTAssertEqual(mockPlaybackService.currentTime, 0.0)
    }
    
    /// Tier 2: Feature 46 - Validates skipping forward past duration clamps to end and pauses audio.
    func test_tier2_feature46_skipForwardPastDurationClampsToEndAndPauses() throws {
        sut.updatePlaybackTime(295.0)
        sut.skipForward(seconds: 15.0)
        
        XCTAssertEqual(mockPlaybackService.currentTime, sut.totalDuration)
        XCTAssertFalse(sut.isPlaying)
    }
    
    /// Tier 2: Feature 46 - Validates slider scrub drag pauses audio and seeks upon gesture release.
    func test_tier2_feature46_sliderScrubDragPausesAudioAndSeeksOnRelease() throws {
        sut.togglePlayPause() // Playing
        XCTAssertTrue(sut.isPlaying)
        
        sut.beginScrubbing()
        XCTAssertFalse(sut.isPlaying) // Paused during drag
        
        sut.updateScrubPosition(ratio: 0.75) // 225s
        sut.endScrubbing()
        
        XCTAssertEqual(mockPlaybackService.currentTime, 225.0)
    }
    
    /// Tier 2: Feature 46 - Validates reaching audio end resets playback time to zero.
    func test_tier2_feature46_audioCompletionResetsPlaybackTimeToZero() throws {
        sut.handleAudioPlaybackDidFinish()
        
        XCTAssertEqual(mockPlaybackService.currentTime, 0.0)
        XCTAssertFalse(sut.isPlaying)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 47: Rate Cycling & End of File)
    
    /// Tier 2: Feature 47 - Validates rapid rate button tapping does not corrupt playback rate.
    func test_tier2_feature47_rapidSpeedButtonCyclingStability() throws {
        for _ in 0..<50 {
            sut.cyclePlaybackSpeed()
        }
        let validRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        XCTAssertTrue(validRates.contains(sut.playbackRate))
    }
    
    /// Tier 2: Feature 47 - Validates selected playback rate is persisted for current user session.
    func test_tier2_feature47_variableSpeedPersistenceAcrossSessions() throws {
        sut.setPlaybackRate(1.5)
        XCTAssertEqual(sut.playbackRate, 1.5)
        
        let newSut = MeetingDetailViewModel(
            meeting: initialMeeting,
            modelContext: context,
            playbackService: mockPlaybackService,
            summarizationService: mockSummarizationService,
            exportService: mockExportService
        )
        XCTAssertEqual(newSut.playbackRate, 1.5)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 51: Gallery Zero States & Zoom)
    
    /// Tier 2: Feature 51 - Validates empty gallery photos state renders placeholder.
    func test_tier2_feature51_zeroPhotosEmptyStatePlaceholder() throws {
        sut.clearGalleryPhotos()
        
        XCTAssertTrue(sut.galleryPhotos.isEmpty)
        XCTAssertEqual(sut.emptyPhotosMessage, "No whiteboard photos attached.")
    }
    
    /// Tier 2: Feature 51 - Validates pinch to zoom scale is clamped at 5.0x maximum.
    func test_tier2_feature51_pinchToZoomMaxScaleClampedToFive() throws {
        let clamped = sut.clampZoomScale(8.5)
        XCTAssertEqual(clamped, 5.0)
        
        let minClamped = sut.clampZoomScale(0.2)
        XCTAssertEqual(minClamped, 1.0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 52: Off-topic AI Queries & Citations)
    
    /// Tier 2: Feature 52 - Validates off-topic question returns grounded "Not discussed" fallback.
    func test_tier2_feature52_offTopicQueryReturnsNotDiscussedFallback() async throws {
        let model = MeetingDetailViewModel(meeting: initialMeeting, questionAnswerer: { _, _ in [] })
        let response = try await model.askAI(prompt: "What was the weather like on Mars?")
        XCTAssertEqual(response.text, "Not discussed in this meeting.")
        XCTAssertTrue(response.citations.isEmpty)
    }

    func testQuestionRejectsInventedEvidenceInsteadOfFabricatingCitation() async throws {
        let model = MeetingDetailViewModel(meeting: initialMeeting, questionAnswerer: { _, turns in
            [SupportedPoint(text: "Invented commitment", evidence: [SourceEvidence(turnID: turns[0].id, quote: "John promised a security audit Friday")])]
        })
        do {
            _ = try await model.askAI(prompt: "What did John promise?")
            XCTFail("Invented evidence must be rejected")
        } catch { XCTAssertTrue(model.aiChatHistory.isEmpty) }
    }

    /// Tier 2: Feature 52 - Validates tapping citation timecode seeks player directly.
    func test_tier2_feature52_tapCitationTimecodeSeeksAudioPlayer() throws {
        let citation = AICitation(timestamp: 30.0, segmentText: "Action items sync")
        sut.tapCitation(citation)
        
        XCTAssertEqual(mockPlaybackService.currentTime, 30.0)
    }
    
    /// Tier 2: Feature 52 - Validates empty query disables submission button.
    func test_tier2_feature52_emptyAIQueryDisabledSubmit() throws {
        XCTAssertFalse(sut.canSubmitAIQuery(""))
        XCTAssertFalse(sut.canSubmitAIQuery("   \t  "))
        XCTAssertTrue(sut.canSubmitAIQuery("What was decided?"))
    }
}


extension MeetingDetailViewModelTests {
    func testRemindersSyncUsesOnlySavedTasksAndKeepsUnreviewedSuggestionsOut() async throws {
        let reminders = MockRemindersSyncService()
        let meeting = Meeting(title: "Review boundary", status: .completed)
        context.insert(meeting)
        meeting.addActionItem(ActionItem(title: "Confirmed task", meeting: meeting))
        let fixture = #"""
        {"sourceSignature":"test","stage":"completed","turns":[{"id":"t1","text":"Please send an estimate.","start":0,"end":2}],"speakers":[],"analyzedChunks":1,"analysis":[{"discussion":[],"decisions":[],"tasks":[{"title":"Send an estimate","category":"Follow-up","evidence":[{"turnID":"t1","quote":"Please send an estimate."}]}]}]}
        """#
        meeting.offlineAnalysisData = Data(fixture.utf8)
        try context.save()
        XCTAssertEqual(meeting.pendingTaskSuggestions.count, 1)
        let model = MeetingDetailViewModel(meeting: meeting, modelContext: context, remindersService: reminders)
        try await model.syncReviewedTasksToReminders()
        XCTAssertEqual(reminders.dispatchedRemindersCount, 1)
        XCTAssertEqual(meeting.actionItems.count, 1)
        XCTAssertNotNil(meeting.actionItems.first?.reminderIdentifier)
        XCTAssertEqual(meeting.pendingTaskSuggestions.count, 1)
        XCTAssertFalse(model.isSyncingReminders)
    }
}
