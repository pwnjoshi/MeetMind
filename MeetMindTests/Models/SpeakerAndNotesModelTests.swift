//
//  SpeakerAndNotesModelTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying Speaker, Note, Folder, Tag, Summary,
//  and TranscriptSegment model schemas, relational integrity, and formatting logic.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class SpeakerAndNotesModelTests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
            Speaker.self,
            Summary.self,
            ActionItem.self,
            Note.self,
            Tag.self,
            Folder.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Speaker Model Tests (Feature 1, Feature 25)
    
    /// Tier 1: Feature 25 - Validates default speaker initialization.
    func test_tier1_feature25_speakerDefaultInitialization() throws {
        let speaker = Speaker(name: "Sarah Connor")
        XCTAssertNotNil(speaker.id)
        XCTAssertEqual(speaker.name, "Sarah Connor")
        XCTAssertNil(speaker.email)
        XCTAssertNil(speaker.role)
        XCTAssertEqual(speaker.avatarColorHex, "#3B82F6")
        XCTAssertNil(speaker.voiceSampleURL)
        XCTAssertTrue(speaker.meetings.isEmpty)
        XCTAssertTrue(speaker.transcriptSegments.isEmpty)
        XCTAssertTrue(speaker.assignedActionItems.isEmpty)
    }
    
    /// Tier 1: Feature 25 - Validates custom speaker initialization.
    func test_tier1_feature25_speakerCustomInitialization() throws {
        let customID = UUID()
        let sampleURL = URL(fileURLWithPath: "/tmp/voice_sample.m4a")
        let speaker = Speaker(
            id: customID,
            name: "Dr. Alexander Rivera",
            email: "alex@meetmind.ai",
            role: "Principal AI Architect",
            avatarColorHex: "#8B5CF6",
            voiceSampleURL: sampleURL
        )
        
        XCTAssertEqual(speaker.id, customID)
        XCTAssertEqual(speaker.name, "Dr. Alexander Rivera")
        XCTAssertEqual(speaker.email, "alex@meetmind.ai")
        XCTAssertEqual(speaker.role, "Principal AI Architect")
        XCTAssertEqual(speaker.avatarColorHex, "#8B5CF6")
        XCTAssertEqual(speaker.voiceSampleURL, sampleURL)
    }
    
    /// Tier 1: Feature 25 - Validates initials calculation for multi-word names.
    func test_tier1_feature25_speakerInitialsMultiWord() throws {
        let speaker = Speaker(name: "Sarah Connor")
        XCTAssertEqual(speaker.initials, "SC")
        
        let speakerThreeWords = Speaker(name: "John Ronald Tolkien")
        XCTAssertEqual(speakerThreeWords.initials, "JR")
    }
    
    /// Tier 1: Feature 25 - Validates initials calculation for single-word names.
    func test_tier1_feature25_speakerInitialsSingleWord() throws {
        let speaker = Speaker(name: "Madonna")
        XCTAssertEqual(speaker.initials, "M")
    }
    
    /// Tier 1: Feature 25 - Validates displayLabel with and without role.
    func test_tier1_feature25_speakerDisplayLabel() throws {
        let speakerWithRole = Speaker(name: "Alice Wang", role: "Staff Engineer")
        XCTAssertEqual(speakerWithRole.displayLabel, "Alice Wang (Staff Engineer)")
        
        let speakerWithoutRole = Speaker(name: "Bob Stone")
        XCTAssertEqual(speakerWithoutRole.displayLabel, "Bob Stone")
        
        let speakerEmptyRole = Speaker(name: "Charlie Brown", role: "")
        XCTAssertEqual(speakerEmptyRole.displayLabel, "Charlie Brown")
    }
    
    // MARK: - Tier 1: Note Model Tests (Feature 1, Feature 32, 33, 35)
    
    /// Tier 1: Feature 32 - Validates note default initialization.
    func test_tier1_feature32_noteDefaultInitialization() throws {
        let note = Note(content: "Discuss deployment timeline")
        XCTAssertNotNil(note.id)
        XCTAssertEqual(note.content, "Discuss deployment timeline")
        XCTAssertEqual(note.timestamp, 0.0)
        XCTAssertFalse(note.isBookmark)
        XCTAssertNil(note.imageAttachmentPath)
        XCTAssertFalse(note.hasImage)
        XCTAssertNil(note.meeting)
    }
    
    /// Tier 1: Feature 32 - Validates note formatted timestamp calculation.
    func test_tier1_feature32_noteFormattedTimestamp() throws {
        let note = Note(content: "Important discussion", timestamp: 145.0)
        XCTAssertEqual(note.formattedTimestamp, "02:25")
    }
    
    /// Tier 1: Feature 33 - Validates bookmark note initialization.
    func test_tier1_feature33_bookmarkNoteFlag() throws {
        let bookmark = Note(content: "Key decision point flagged", timestamp: 310.0, isBookmark: true)
        XCTAssertTrue(bookmark.isBookmark)
        XCTAssertEqual(bookmark.formattedTimestamp, "05:10")
    }
    
    /// Tier 1: Feature 35 - Validates whiteboard media attachment path.
    func test_tier1_feature35_noteWhiteboardImageAttachment() throws {
        let photoNote = Note(
            content: "Whiteboard architecture diagram",
            timestamp: 600.0,
            imageAttachmentPath: "Attachments/whiteboard_01.jpg"
        )
        XCTAssertTrue(photoNote.hasImage)
        XCTAssertEqual(photoNote.imageAttachmentPath, "Attachments/whiteboard_01.jpg")
    }
    
    // MARK: - Tier 1: Folder & Tag Model Tests (Feature 1, Feature 28)
    
    /// Tier 1: Feature 28 - Validates folder initialization and defaults.
    func test_tier1_feature28_folderInitialization() throws {
        let folder = Folder(name: "Product Roadmap")
        XCTAssertNotNil(folder.id)
        XCTAssertEqual(folder.name, "Product Roadmap")
        XCTAssertEqual(folder.iconName, "folder.fill")
        XCTAssertEqual(folder.colorHex, "#3B82F6")
        XCTAssertTrue(folder.meetings.isEmpty)
    }
    
    /// Tier 1: Feature 28 - Validates tag initialization and meetingCount property.
    func test_tier1_feature28_tagInitialization() throws {
        let tag = Tag(name: "Design-Sprint", colorHex: "#10B981")
        XCTAssertNotNil(tag.id)
        XCTAssertEqual(tag.name, "Design-Sprint")
        XCTAssertEqual(tag.colorHex, "#10B981")
        XCTAssertEqual(tag.meetingCount, 0)
    }
    
    // MARK: - Tier 1: Summary Model Tests (Feature 1, Feature 41)
    
    /// Tier 1: Feature 41 - Validates summary initialization and helper properties.
    func test_tier1_feature41_summaryInitialization() throws {
        let summary = Summary(
            executiveSummary: "The team agreed to proceed with Milestone 1 architecture.",
            keyPoints: ["Point 1", "Point 2", "Point 3"],
            keyDecisions: ["Decision 1", "Decision 2"]
        )
        
        XCTAssertNotNil(summary.id)
        XCTAssertEqual(summary.executiveSummary, "The team agreed to proceed with Milestone 1 architecture.")
        XCTAssertEqual(summary.keyPointsCount, 3)
        XCTAssertEqual(summary.keyDecisionsCount, 2)
        XCTAssertEqual(summary.modelVersion, "Apple-NaturalLanguage-Extractive-v1")
        XCTAssertFalse(summary.formattedGeneratedDate.isEmpty)
        XCTAssertNil(summary.meeting)
    }
    
    // MARK: - Tier 1: TranscriptSegment Model Tests (Feature 1, Feature 42, 44)
    
    /// Tier 1: Feature 42 - Validates transcript segment initialization and duration.
    func test_tier1_feature42_transcriptSegmentInitialization() throws {
        let speaker = Speaker(name: "Alice")
        let segment = TranscriptSegment(
            text: "Let's review the system architecture.",
            startTime: 12.0,
            endTime: 16.5,
            confidence: 0.98,
            isEdited: false,
            speaker: speaker
        )
        
        XCTAssertNotNil(segment.id)
        XCTAssertEqual(segment.text, "Let's review the system architecture.")
        XCTAssertEqual(segment.startTime, 12.0)
        XCTAssertEqual(segment.endTime, 16.5)
        XCTAssertEqual(segment.duration, 4.5)
        XCTAssertEqual(segment.confidence, 0.98)
        XCTAssertFalse(segment.isEdited)
        XCTAssertEqual(segment.speakerDisplayName, "Alice")
        XCTAssertEqual(segment.formattedStartTime, "00:12")
        XCTAssertEqual(segment.formattedEndTime, "00:16")
        XCTAssertEqual(segment.formattedTimeRange, "00:12 - 00:16")
    }
    
    /// Tier 1: Feature 44 - Validates transcript inline editor update helper.
    func test_tier1_feature44_transcriptSegmentUpdateText() throws {
        let segment = TranscriptSegment(text: "Original speech typo", startTime: 5.0, endTime: 8.0)
        XCTAssertFalse(segment.isEdited)
        
        segment.updateText("Corrected speech text")
        XCTAssertEqual(segment.text, "Corrected speech text")
        XCTAssertTrue(segment.isEdited)
    }
    
    /// Tier 1: Feature 42 - Validates speakerDisplayName fallback when speaker is nil.
    func test_tier1_feature42_speakerDisplayNameFallback() throws {
        let segment = TranscriptSegment(text: "Unattributed speech", startTime: 0, endTime: 2)
        XCTAssertEqual(segment.speakerDisplayName, "Unknown Speaker")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    /// Tier 2: Feature 25 - Validates initials fallback for empty name.
    func test_tier2_feature25_emptySpeakerNameInitials() throws {
        let emptySpeaker = Speaker(name: "")
        XCTAssertEqual(emptySpeaker.initials, "?")
    }
    
    /// Tier 2: Feature 42 - Validates transcript segment with inverted or identical timestamps.
    func test_tier2_feature42_invertedTimestampsClampedDuration() throws {
        let invertedSegment = TranscriptSegment(text: "Glitch", startTime: 20.0, endTime: 10.0)
        XCTAssertEqual(invertedSegment.duration, 0.0) // clamped to max(0, endTime - startTime)
        
        let zeroDurationSegment = TranscriptSegment(text: "Click", startTime: 5.0, endTime: 5.0)
        XCTAssertEqual(zeroDurationSegment.duration, 0.0)
    }
    
    /// Tier 2: Feature 42 - Validates 0 confidence score handling.
    func test_tier2_feature42_zeroConfidenceScore() throws {
        let lowConfSegment = TranscriptSegment(text: "Indistinct murmur", startTime: 1.0, endTime: 3.0, confidence: 0.0)
        XCTAssertEqual(lowConfSegment.confidence, 0.0)
    }
    
    /// Tier 2: Feature 32 - Validates massive note content (10,000 characters).
    func test_tier2_feature32_massiveNoteContent() throws {
        let massiveContent = String(repeating: "Meeting minutes notes paragraph. ", count: 300)
        let note = Note(content: massiveContent, timestamp: 99.0)
        context.insert(note)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(fetched.first?.content.count, massiveContent.count)
    }
    
    /// Tier 2: Feature 41 - Validates summary with empty keyPoints and keyDecisions arrays.
    func test_tier2_feature41_emptySummaryCollections() throws {
        let emptySummary = Summary(executiveSummary: "Short meeting.", keyPoints: [], keyDecisions: [])
        XCTAssertEqual(emptySummary.keyPointsCount, 0)
        XCTAssertEqual(emptySummary.keyDecisionsCount, 0)
        context.insert(emptySummary)
        XCTAssertNoThrow(try context.save())
    }
    
    /// Tier 2: Feature 28 - Validates folder with custom icon and hex color.
    func test_tier2_feature28_customFolderStyling() throws {
        let folder = Folder(name: "Confidential", iconName: "lock.shield.fill", colorHex: "#DC2626")
        XCTAssertEqual(folder.iconName, "lock.shield.fill")
        XCTAssertEqual(folder.colorHex, "#DC2626")
    }
    
    // MARK: - Tier 3: Pairwise Invariants & Relational Integrity
    
    /// Tier 3: Pairwise - Verifies deleting a Speaker preserves associated TranscriptSegments (nullify rule).
    func test_tier3_speakerDeletionNullifiesSegmentSpeaker() throws {
        let speaker = Speaker(name: "Guest Speaker")
        let segment = TranscriptSegment(text: "Opening remarks", startTime: 0, endTime: 10, speaker: speaker)
        context.insert(speaker)
        context.insert(segment)
        try context.save()
        
        XCTAssertEqual(segment.speaker?.name, "Guest Speaker")
        
        context.delete(speaker)
        try context.save()
        
        let remainingSegments = try context.fetch(FetchDescriptor<TranscriptSegment>())
        XCTAssertEqual(remainingSegments.count, 1)
        XCTAssertNil(remainingSegments.first?.speaker)
        XCTAssertEqual(remainingSegments.first?.speakerDisplayName, "Unknown Speaker")
    }
    
    /// Tier 3: Pairwise - Verifies Summary relationship with Meeting is cascade-deleted.
    func test_tier3_summaryCascadeDeletedWithMeeting() throws {
        let meeting = Meeting(title: "Architecture Summit")
        let summary = Summary(executiveSummary: "Summit recap")
        meeting.summary = summary
        context.insert(meeting)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Summary>()).count, 1)
        
        context.delete(meeting)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Summary>()).count, 0)
    }
    
    /// Tier 3: Pairwise - Verifies Note relationship with Meeting is cascade-deleted.
    func test_tier3_notesCascadeDeletedWithMeeting() throws {
        let meeting = Meeting(title: "Design Review")
        let note1 = Note(content: "Check contrast ratio", timestamp: 10.0)
        let note2 = Note(content: "Audit touch targets", timestamp: 20.0, isBookmark: true)
        meeting.addNote(note1)
        meeting.addNote(note2)
        context.insert(meeting)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 2)
        
        context.delete(meeting)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 0)
    }
    
    /// Tier 1: Feature 25 - Validates speaker voiceSampleURL assignment.
    func test_tier1_feature25_speakerVoiceSampleURLAssignment() throws {
        let speaker = Speaker(name: "Voice Test")
        XCTAssertNil(speaker.voiceSampleURL)
        let sampleURL = URL(fileURLWithPath: "/tmp/sample.m4a")
        speaker.voiceSampleURL = sampleURL
        XCTAssertEqual(speaker.voiceSampleURL, sampleURL)
    }
    
    /// Tier 1: Feature 25 - Validates speaker initials calculation with extra whitespace.
    func test_tier1_feature25_speakerInitialsWithExtraWhitespace() throws {
        let speaker = Speaker(name: "  Sarah   Connor  ")
        XCTAssertEqual(speaker.initials, "SC")
    }
    
    /// Tier 1: Feature 32 - Validates note createdAt defaults to current date.
    func test_tier1_feature32_noteCreatedAtDefaultsToNow() throws {
        let before = Date().addingTimeInterval(-1)
        let note = Note(content: "Timestamp test")
        let after = Date().addingTimeInterval(1)
        XCTAssertTrue(note.createdAt >= before && note.createdAt <= after)
    }
    
    /// Tier 1: Feature 28 - Validates tag colorHex defaults to purple #8B5CF6.
    func test_tier1_feature28_tagColorHexDefaultsToPurple() throws {
        let tag = Tag(name: "DefaultColor")
        XCTAssertEqual(tag.colorHex, "#8B5CF6")
    }
    
    /// Tier 1: Feature 42 - Validates transcript segment confidence default value.
    func test_tier1_feature42_transcriptSegmentConfidenceDefault() throws {
        let segment = TranscriptSegment(text: "Speech", startTime: 0, endTime: 2)
        XCTAssertEqual(segment.confidence, 1.0)
    }
    
    /// Tier 2: Feature 42 - Validates transcript segment formatted times with large offsets.
    func test_tier2_feature42_transcriptSegmentFormattedTimesWithLargeOffsets() throws {
        let segment = TranscriptSegment(text: "Late speech", startTime: 3665.0, endTime: 3720.0)
        XCTAssertEqual(segment.formattedStartTime, "61:05")
        XCTAssertEqual(segment.formattedEndTime, "62:00")
    }
    
    /// Tier 2: Feature 28 - Validates folder meetings count incrementing as meetings are added.
    func test_tier2_feature28_folderMeetingCount() throws {
        let folder = Folder(name: "Engineering")
        XCTAssertEqual(folder.meetings.count, 0)
        let m = Meeting(title: "Sprint 1")
        folder.meetings.append(m)
        XCTAssertEqual(folder.meetings.count, 1)
    }
    
    /// Tier 3: Pairwise - Verifies Speaker assignedActionItems relationship persistence.
    func test_tier3_speakerAssignedActionItemsPersistence() throws {
        let speaker = Speaker(name: "Task Owner")
        let item1 = ActionItem(title: "Task 1", assignee: speaker)
        let item2 = ActionItem(title: "Task 2", assignee: speaker)
        speaker.assignedActionItems.append(item1)
        speaker.assignedActionItems.append(item2)
        context.insert(speaker)
        try context.save()
        
        let fetchedSpeaker = try context.fetch(FetchDescriptor<Speaker>()).first
        XCTAssertEqual(fetchedSpeaker?.assignedActionItems.count, 2)
    }
}
