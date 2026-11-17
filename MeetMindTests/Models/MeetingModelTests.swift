//
//  MeetingModelTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying Meeting model schema, relational integrity,
//  cascade deletion rules, state transitions, and formatting helpers.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class MeetingModelTests: XCTestCase {
    @MainActor
    func testProductionSchemaPersistsAcrossContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(
            schema: ModelContainerFactory.schema,
            url: directory.appendingPathComponent("meetings.store"),
            cloudKitDatabase: .none
        )
        let id = UUID()
        do {
            let container = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
            let context = container.mainContext
            let meeting = Meeting(id: id, title: "Relaunch regression")
            context.insert(meeting)
            meeting.addNote(Note(content: "Persist this note", timestamp: 1))
            meeting.addActionItem(ActionItem(title: "Persist this action"))
            try context.save()
        }
        let reopened = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        let restored = try XCTUnwrap(reopened.mainContext.fetch(descriptor).first)
        XCTAssertEqual(restored.title, "Relaunch regression")
        XCTAssertEqual(restored.notes.first?.content, "Persist this note")
        XCTAssertEqual(restored.actionItems.first?.title, "Persist this action")
    }
    
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
    
    // MARK: - Tier 1: Feature Coverage (Feature 1: SwiftData Models & Schemas)
    
    /// Tier 1: Feature 1 - Validates default initialization values and UUID uniqueness.
    func test_tier1_feature1_meetingInitializationDefaults() throws {
        let meeting = Meeting(title: "Architecture Strategy Sync")
        XCTAssertNotNil(meeting.id)
        XCTAssertEqual(meeting.title, "Architecture Strategy Sync")
        XCTAssertEqual(meeting.status, .scheduled)
        XCTAssertEqual(meeting.duration, 0.0)
        XCTAssertFalse(meeting.isFavorite)
        XCTAssertEqual(meeting.audioQuality, .standard)
        XCTAssertNil(meeting.audioFileURL)
        XCTAssertNil(meeting.scheduledStartTime)
        XCTAssertNil(meeting.templateName)
        XCTAssertNil(meeting.folder)
        XCTAssertTrue(meeting.tags.isEmpty)
        XCTAssertTrue(meeting.transcriptSegments.isEmpty)
        XCTAssertNil(meeting.summary)
        XCTAssertTrue(meeting.actionItems.isEmpty)
        XCTAssertTrue(meeting.notes.isEmpty)
        XCTAssertTrue(meeting.participants.isEmpty)
    }
    
    /// Tier 1: Feature 1 - Validates custom initialization with all parameters supplied.
    func test_tier1_feature1_meetingCustomInitialization() throws {
        let customID = UUID()
        let created = Date(timeIntervalSince1970: 1700000000)
        let scheduled = Date(timeIntervalSince1970: 1700003600)
        let url = URL(fileURLWithPath: "/tmp/sample.m4a")
        
        let meeting = Meeting(
            id: customID,
            title: "Executive Review",
            createdAt: created,
            scheduledStartTime: scheduled,
            duration: 3600.0,
            status: .recording,
            audioFileURL: url,
            audioQuality: .high,
            isFavorite: true,
            templateName: "Executive"
        )
        
        XCTAssertEqual(meeting.id, customID)
        XCTAssertEqual(meeting.title, "Executive Review")
        XCTAssertEqual(meeting.createdAt, created)
        XCTAssertEqual(meeting.scheduledStartTime, scheduled)
        XCTAssertEqual(meeting.duration, 3600.0)
        XCTAssertEqual(meeting.status, .recording)
        XCTAssertEqual(meeting.audioFileURL, url)
        XCTAssertEqual(meeting.audioQuality, .high)
        XCTAssertTrue(meeting.isFavorite)
        XCTAssertEqual(meeting.templateName, "Executive")
    }
    
    /// Tier 1: Feature 1 - Validates persistence in memory ModelContext.
    func test_tier1_feature1_meetingPersistenceInContext() throws {
        let meeting = Meeting(title: "Sprint Planning")
        context.insert(meeting)
        try context.save()
        
        let descriptor = FetchDescriptor<Meeting>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Sprint Planning")
    }
    
    /// Tier 1: Feature 1 - Validates favorite toggling helper.
    func test_tier1_feature1_meetingFavoriteToggle() throws {
        let meeting = Meeting(title: "Quick Sync")
        XCTAssertFalse(meeting.isFavorite)
        meeting.toggleFavorite()
        XCTAssertTrue(meeting.isFavorite)
        meeting.toggleFavorite()
        XCTAssertFalse(meeting.isFavorite)
    }
    
    /// Tier 1: Feature 1 - Validates formatted duration for sub-hour meetings.
    func test_tier1_feature1_formattedDurationMinutesSeconds() throws {
        let meeting = Meeting(title: "Short Standup", duration: 125.0)
        XCTAssertEqual(meeting.formattedDuration, "02:05")
    }
    
    /// Tier 1: Feature 1 - Validates formatted duration for multi-hour meetings.
    func test_tier1_feature1_formattedDurationMultiHour() throws {
        let meeting = Meeting(title: "All-Hands", duration: 3665.0)
        XCTAssertEqual(meeting.formattedDuration, "01:01:05")
    }
    
    /// Tier 1: Feature 1 - Validates formatted date using scheduledStartTime fallback to createdAt.
    func test_tier1_feature1_formattedDateOutput() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let meeting = Meeting(title: "Review", createdAt: fixedDate)
        XCTAssertFalse(meeting.formattedDate.isEmpty)
    }
    
    /// Tier 1: Feature 1 - Validates full transcript text synthesis in chronological order.
    func test_tier1_feature1_fullTranscriptTextSynthesis() throws {
        let meeting = Meeting(title: "Transcript Test")
        let speaker = Speaker(name: "Alice")
        let seg1 = TranscriptSegment(text: "Hello everyone", startTime: 10.0, endTime: 12.0, speaker: speaker)
        let seg2 = TranscriptSegment(text: "Welcome to the meeting", startTime: 2.0, endTime: 5.0, speaker: speaker)
        meeting.addTranscriptSegment(seg1)
        meeting.addTranscriptSegment(seg2)
        
        let fullText = meeting.fullTranscriptText
        XCTAssertTrue(fullText.contains("Welcome to the meeting"))
        XCTAssertTrue(fullText.contains("Hello everyone"))
        // seg2 starts at 2.0s, so it must precede seg1 in sorted transcript
        let range2 = fullText.range(of: "Welcome to the meeting")!
        let range1 = fullText.range(of: "Hello everyone")!
        XCTAssertTrue(range2.lowerBound < range1.lowerBound)
    }
    
    /// Tier 1: Feature 1 - Validates pending and completed action item counters.
    func test_tier1_feature1_actionItemCounters() throws {
        let meeting = Meeting(title: "Action Items Test")
        let item1 = ActionItem(title: "Task 1", isCompleted: false)
        let item2 = ActionItem(title: "Task 2", isCompleted: true)
        let item3 = ActionItem(title: "Task 3", isCompleted: false)
        
        meeting.addActionItem(item1)
        meeting.addActionItem(item2)
        meeting.addActionItem(item3)
        
        XCTAssertEqual(meeting.pendingActionItemsCount, 2)
        XCTAssertEqual(meeting.completedActionItemsCount, 1)
    }
    
    /// Tier 1: Feature 1 - Validates hasAudio computed property.
    func test_tier1_feature1_hasAudioProperty() throws {
        let meeting = Meeting(title: "Audio Test")
        XCTAssertFalse(meeting.hasAudio)
        meeting.audioFileURL = URL(fileURLWithPath: "/path/to/meeting.m4a")
        XCTAssertTrue(meeting.hasAudio)
    }
    
    /// Tier 1: Feature 1 - Validates adding and removing participants.
    func test_tier1_feature1_participantManagement() throws {
        let meeting = Meeting(title: "Team Standup")
        let speaker1 = Speaker(name: "Alice", email: "alice@example.com")
        let speaker2 = Speaker(name: "Bob", email: "bob@example.com")
        
        meeting.addParticipant(speaker1)
        meeting.addParticipant(speaker2)
        XCTAssertEqual(meeting.participants.count, 2)
        
        meeting.removeParticipant(speaker1)
        XCTAssertEqual(meeting.participants.count, 1)
        XCTAssertEqual(meeting.participants.first?.name, "Bob")
    }
    
    /// Tier 1: Feature 1 - Validates adding note helper sets inverse relationship.
    func test_tier1_feature1_addNoteRelationship() throws {
        let meeting = Meeting(title: "Note Session")
        let note = Note(content: "Key takeaway point", timestamp: 45.0)
        meeting.addNote(note)
        
        XCTAssertEqual(meeting.notes.count, 1)
        XCTAssertEqual(note.meeting?.id, meeting.id)
    }
    
    // MARK: - Feature 19: Meeting Status Badges & State Machine
    
    /// Tier 1: Feature 19 - Validates all MeetingStatus enum cases and display names.
    func test_tier1_feature19_meetingStatusDisplayNames() throws {
        XCTAssertEqual(MeetingStatus.scheduled.displayName, "Scheduled")
        XCTAssertEqual(MeetingStatus.recording.displayName, "Recording")
        XCTAssertEqual(MeetingStatus.processing.displayName, "Processing")
        XCTAssertEqual(MeetingStatus.completed.displayName, "Completed")
        XCTAssertEqual(MeetingStatus.archived.displayName, "Archived")
    }
    
    /// Tier 1: Feature 19 - Validates status badge hex color mappings.
    func test_tier1_feature19_meetingStatusBadgeColors() throws {
        XCTAssertEqual(MeetingStatus.scheduled.badgeColorHex, "#3B82F6")
        XCTAssertEqual(MeetingStatus.recording.badgeColorHex, "#EF4444")
        XCTAssertEqual(MeetingStatus.processing.badgeColorHex, "#F59E0B")
        XCTAssertEqual(MeetingStatus.completed.badgeColorHex, "#10B981")
        XCTAssertEqual(MeetingStatus.archived.badgeColorHex, "#6B7280")
    }
    
    /// Tier 1: Feature 19 - Validates status icon SF Symbol mappings.
    func test_tier1_feature19_meetingStatusIcons() throws {
        XCTAssertEqual(MeetingStatus.scheduled.iconName, "calendar")
        XCTAssertEqual(MeetingStatus.recording.iconName, "record.circle.fill")
        XCTAssertEqual(MeetingStatus.processing.iconName, "gearshape.arrow.triangle.2.circlepath")
        XCTAssertEqual(MeetingStatus.completed.iconName, "checkmark.circle.fill")
        XCTAssertEqual(MeetingStatus.archived.iconName, "archivebox.fill")
    }
    
    /// Tier 1: Feature 19 - Validates state machine valid transitions.
    func test_tier1_feature19_validStateTransitions() throws {
        XCTAssertTrue(MeetingStatus.scheduled.canTransition(to: .recording))
        XCTAssertTrue(MeetingStatus.scheduled.canTransition(to: .processing))
        XCTAssertTrue(MeetingStatus.scheduled.canTransition(to: .archived))
        XCTAssertTrue(MeetingStatus.recording.canTransition(to: .processing))
        XCTAssertTrue(MeetingStatus.processing.canTransition(to: .completed))
        XCTAssertTrue(MeetingStatus.completed.canTransition(to: .archived))
        XCTAssertTrue(MeetingStatus.archived.canTransition(to: .completed))
        XCTAssertTrue(MeetingStatus.recording.canTransition(to: .recording)) // identity
    }
    
    /// Tier 1: Feature 19 - Validates state machine invalid transitions.
    func test_tier1_feature19_invalidStateTransitions() throws {
        XCTAssertFalse(MeetingStatus.scheduled.canTransition(to: .completed))
        XCTAssertFalse(MeetingStatus.processing.canTransition(to: .archived))
        XCTAssertFalse(MeetingStatus.completed.canTransition(to: .recording))
    }
    
    // MARK: - AudioQuality Enums
    
    /// Tier 1: AudioQuality - Validates standard and high bitrates and extensions.
    func test_tier1_audioQualityProperties() throws {
        XCTAssertEqual(AudioQuality.standard.bitRate, 64_000)
        XCTAssertEqual(AudioQuality.high.bitRate, 128_000)
        XCTAssertEqual(AudioQuality.standard.fileExtension, "m4a")
        XCTAssertEqual(AudioQuality.high.fileExtension, "m4a")
        XCTAssertEqual(AudioQuality.standard.sampleRate, 44_100.0)
        XCTAssertFalse(AudioQuality.standard.storageEstimatePerHour.isEmpty)
        XCTAssertFalse(AudioQuality.high.storageEstimatePerHour.isEmpty)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 1 & Feature 19)
    
    /// Tier 2: Feature 1 - Validates boundary handling with empty title string.
    func test_tier2_feature1_emptyTitleString() throws {
        let meeting = Meeting(title: "")
        XCTAssertEqual(meeting.title, "")
        context.insert(meeting)
        XCTAssertNoThrow(try context.save())
    }
    
    /// Tier 2: Feature 1 - Validates boundary handling with very long title (10,000 characters).
    func test_tier2_feature1_extremelyLongTitle() throws {
        let longTitle = String(repeating: "MeetMind Scalability Test ", count: 400)
        let meeting = Meeting(title: longTitle)
        context.insert(meeting)
        try context.save()
        
        let descriptor = FetchDescriptor<Meeting>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.title.count, longTitle.count)
    }
    
    /// Tier 2: Feature 1 - Validates zero duration formatting.
    func test_tier2_feature1_zeroDurationFormatting() throws {
        let meeting = Meeting(title: "Instant Sync", duration: 0.0)
        XCTAssertEqual(meeting.formattedDuration, "00:00")
    }
    
    /// Tier 2: Feature 1 - Validates extreme duration of 7 days (604,800 seconds).
    func test_tier2_feature1_extremeMultiDayDuration() throws {
        let meeting = Meeting(title: "Hackathon", duration: 604_800.0)
        XCTAssertEqual(meeting.formattedDuration, "168:00:00")
    }
    
    /// Tier 2: Feature 1 - Validates title containing emojis and unicode characters.
    func test_tier2_feature1_unicodeTitleAndSymbols() throws {
        let title = "🚀 Q4 Strategy & AI 🧠 — (Part 1/2) #Roadmap <Final>"
        let meeting = Meeting(title: title)
        XCTAssertEqual(meeting.title, title)
        context.insert(meeting)
        try context.save()
        
        let descriptor = FetchDescriptor<Meeting>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.title, title)
    }
    
    /// Tier 2: Feature 1 - Validates unrecognized statusRaw falls back safely to scheduled.
    func test_tier2_feature1_invalidStatusRawFallback() throws {
        let meeting = Meeting(title: "Status Fallback")
        meeting.statusRaw = "corrupted_status_string"
        XCTAssertEqual(meeting.status, .scheduled)
    }
    
    /// Tier 2: Feature 1 - Validates unrecognized audioQualityRaw falls back to standard.
    func test_tier2_feature1_invalidAudioQualityRawFallback() throws {
        let meeting = Meeting(title: "Audio Quality Fallback")
        meeting.audioQualityRaw = "super_flac_lossless"
        XCTAssertEqual(meeting.audioQuality, .standard)
    }
    
    /// Tier 2: Feature 1 - Validates duplicate participant insertion is prevented.
    func test_tier2_feature1_duplicateParticipantPrevention() throws {
        let meeting = Meeting(title: "Duplicate Check")
        let speaker = Speaker(name: "Sarah Connor", email: "sarah@resistance.org")
        
        meeting.addParticipant(speaker)
        meeting.addParticipant(speaker) // duplicate attempt with identical ID
        XCTAssertEqual(meeting.participants.count, 1)
    }
    
    /// Tier 2: Feature 1 - Validates removing non-existent participant causes no crash.
    func test_tier2_feature1_removeNonExistentParticipant() throws {
        let meeting = Meeting(title: "Remove Check")
        let speaker1 = Speaker(name: "Alice")
        let speaker2 = Speaker(name: "Bob")
        
        meeting.addParticipant(speaker1)
        meeting.removeParticipant(speaker2) // speaker2 was never added
        XCTAssertEqual(meeting.participants.count, 1)
        XCTAssertEqual(meeting.participants.first?.id, speaker1.id)
    }
    
    /// Tier 2: Feature 1 - Validates full transcript synthesis with zero transcript segments.
    func test_tier2_feature1_fullTranscriptWithZeroSegments() throws {
        let meeting = Meeting(title: "Empty Segments")
        XCTAssertEqual(meeting.fullTranscriptText, "")
    }
    
    /// Tier 2: Feature 1 - Validates rapid favorite toggle stability.
    func test_tier2_feature1_rapidFavoriteToggle() throws {
        let meeting = Meeting(title: "Toggle Stress")
        for _ in 0..<100 {
            meeting.toggleFavorite()
        }
        XCTAssertFalse(meeting.isFavorite) // 100 toggles returns to initial false
    }
    
    /// Tier 2: Feature 19 - Validates state transition to itself is allowed.
    func test_tier2_feature19_selfTransitionAllowed() throws {
        for status in MeetingStatus.allCases {
            XCTAssertTrue(status.canTransition(to: status))
        }
    }
    
    // MARK: - Tier 3: Pairwise & Cascade Deletion Integration
    
    /// Tier 3: Pairwise - Verifies that deleting a Meeting cascade-deletes all its child entities.
    func test_tier3_meetingCascadeDeleteCleansChildEntities() throws {
        let meeting = Meeting(title: "Master Meeting")
        context.insert(meeting)
        
        let speaker = Speaker(name: "Presenter")
        context.insert(speaker)
        meeting.addParticipant(speaker)
        
        let segment1 = TranscriptSegment(text: "Segment 1", startTime: 0, endTime: 5, speaker: speaker)
        let segment2 = TranscriptSegment(text: "Segment 2", startTime: 5, endTime: 10, speaker: speaker)
        meeting.addTranscriptSegment(segment1)
        meeting.addTranscriptSegment(segment2)
        
        let summary = Summary(executiveSummary: "Executive recap text", keyPoints: ["Pt 1"], keyDecisions: ["Dec 1"])
        meeting.summary = summary
        
        let action1 = ActionItem(title: "Action 1", assignee: speaker)
        let action2 = ActionItem(title: "Action 2")
        meeting.addActionItem(action1)
        meeting.addActionItem(action2)
        
        let note1 = Note(content: "Live Note 1", timestamp: 12.0)
        meeting.addNote(note1)
        
        try context.save()
        
        // Confirm child entities exist
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptSegment>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Summary>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActionItem>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Speaker>()).count, 1)
        
        // Delete Meeting
        context.delete(meeting)
        try context.save()
        
        // Verify cascade deletion
        XCTAssertEqual(try context.fetch(FetchDescriptor<Meeting>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TranscriptSegment>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Summary>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActionItem>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 0)
        
        // Shared speaker profile must NOT be deleted
        XCTAssertEqual(try context.fetch(FetchDescriptor<Speaker>()).count, 1)
    }
    
    /// Tier 3: Pairwise - Verifies Folder nullify rule preserves meetings when folder is deleted.
    func test_tier3_folderNullifyPreservesMeetings() throws {
        let folder = Folder(name: "Product Operations")
        context.insert(folder)
        
        let m1 = Meeting(title: "Roadmap Sync", folder: folder)
        let m2 = Meeting(title: "Backlog Grooming", folder: folder)
        context.insert(m1)
        context.insert(m2)
        folder.meetings.append(m1)
        folder.meetings.append(m2)
        try context.save()
        
        XCTAssertEqual(folder.meetings.count, 2)
        XCTAssertEqual(m1.folder?.name, "Product Operations")
        
        // Delete folder
        context.delete(folder)
        try context.save()
        
        let remainingMeetings = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(remainingMeetings.count, 2)
        for m in remainingMeetings {
            XCTAssertNil(m.folder)
        }
    }
    
    /// Tier 3: Pairwise - Verifies Tag many-to-many relationship with multiple meetings.
    func test_tier3_tagManyToManyRelationship() throws {
        let tag = Tag(name: "Urgent", colorHex: "#EF4444")
        context.insert(tag)
        
        let m1 = Meeting(title: "Incident Post-Mortem")
        let m2 = Meeting(title: "Hotfix Planning")
        context.insert(m1)
        context.insert(m2)
        
        m1.tags.append(tag)
        m2.tags.append(tag)
        tag.meetings.append(m1)
        tag.meetings.append(m2)
        try context.save()
        
        XCTAssertEqual(tag.meetingCount, 2)
        XCTAssertTrue(m1.tags.contains { $0.name == "Urgent" })
        XCTAssertTrue(m2.tags.contains { $0.name == "Urgent" })
        
        // Remove tag from one meeting
        m1.tags.removeAll { $0.name == "Urgent" }
        try context.save()
        
        XCTAssertFalse(m1.tags.contains { $0.name == "Urgent" })
        XCTAssertTrue(m2.tags.contains { $0.name == "Urgent" })
    }
    
    /// Tier 3: Pairwise - Verifies MeetingFilter enum matches correctly.
    func test_tier3_meetingFilterEvaluation() throws {
        let now = Date()
        let todayMeeting = Meeting(title: "Today's Discussion", createdAt: now)
        todayMeeting.toggleFavorite()
        
        let yesterdayMeeting = Meeting(title: "Past Discussion", createdAt: now.addingTimeInterval(-86400 * 2))
        let meetingWithActions = Meeting(title: "Action Meeting", createdAt: now)
        meetingWithActions.addActionItem(ActionItem(title: "Review PR"))
        
        XCTAssertTrue(MeetingFilter.all.matches(meeting: todayMeeting))
        XCTAssertTrue(MeetingFilter.today.matches(meeting: todayMeeting))
        XCTAssertFalse(MeetingFilter.today.matches(meeting: yesterdayMeeting))
        XCTAssertTrue(MeetingFilter.starred.matches(meeting: todayMeeting))
        XCTAssertFalse(MeetingFilter.starred.matches(meeting: yesterdayMeeting))
        XCTAssertTrue(MeetingFilter.hasActionItems.matches(meeting: meetingWithActions))
        XCTAssertFalse(MeetingFilter.hasActionItems.matches(meeting: todayMeeting))
    }
    
    /// Tier 1: Feature 1 - Validates addTranscriptSegment sets inverse meeting relationship.
    func test_tier1_feature1_addTranscriptSegmentSetsInverseMeeting() throws {
        let meeting = Meeting(title: "Inverse Segment Test")
        let segment = TranscriptSegment(text: "Hello team", startTime: 0, endTime: 3)
        meeting.addTranscriptSegment(segment)
        XCTAssertEqual(meeting.transcriptSegments.count, 1)
        XCTAssertEqual(segment.meeting?.id, meeting.id)
    }
    
    /// Tier 1: Feature 1 - Validates addActionItem sets inverse meeting relationship.
    func test_tier1_feature1_addActionItemSetsInverseMeeting() throws {
        let meeting = Meeting(title: "Inverse Action Test")
        let item = ActionItem(title: "Follow up with client")
        meeting.addActionItem(item)
        XCTAssertEqual(meeting.actionItems.count, 1)
        XCTAssertEqual(item.meeting?.id, meeting.id)
    }
    
    /// Tier 1: Feature 1 - Validates statusDisplayName and icon reflect statusRaw mutation.
    func test_tier1_feature1_statusDisplayNameAndIconReflectStatusRaw() throws {
        let meeting = Meeting(title: "Status Test")
        meeting.status = .archived
        XCTAssertEqual(meeting.status.displayName, "Archived")
        XCTAssertEqual(meeting.status.iconName, "archivebox.fill")
    }
    
    /// Tier 1: Feature 1 - Validates formattedDuration with various second offsets.
    func test_tier1_feature1_formattedDurationWithVariousSeconds() throws {
        let m1 = Meeting(title: "M1", duration: 59.0)
        XCTAssertEqual(m1.formattedDuration, "00:59")
        let m2 = Meeting(title: "M2", duration: 60.0)
        XCTAssertEqual(m2.formattedDuration, "01:00")
        let m3 = Meeting(title: "M3", duration: 3599.0)
        XCTAssertEqual(m3.formattedDuration, "59:59")
    }
    
    /// Tier 2: Feature 1 - Validates state transition from archived back to completed.
    func test_tier2_feature1_statusRawArchivedTransitionBackToCompleted() throws {
        let meeting = Meeting(title: "Unarchive Test", status: .archived)
        XCTAssertTrue(meeting.status.canTransition(to: .completed))
        meeting.status = .completed
        XCTAssertEqual(meeting.status, .completed)
    }
    
    /// Tier 2: Feature 1 - Validates nil folder initialization explicitly.
    func test_tier2_feature1_nilFolderInitialization() throws {
        let meeting = Meeting(title: "No Folder Meeting", folder: nil)
        XCTAssertNil(meeting.folder)
    }
    
    /// Tier 2: Feature 1 - Validates nil scheduledStartTime uses createdAt for formattedDate.
    func test_tier2_feature1_nilScheduledStartTimeUsesCreatedAtForFormattedDate() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let meeting = Meeting(title: "Date Fallback", createdAt: fixedDate, scheduledStartTime: nil)
        XCTAssertFalse(meeting.formattedDate.isEmpty)
    }
    
    /// Tier 2: Feature 1 - Validates meeting tags array is empty by default and appends correctly.
    func test_tier2_feature1_meetingTagsEmptyByDefault() throws {
        let meeting = Meeting(title: "Tag Addition")
        XCTAssertTrue(meeting.tags.isEmpty)
        let tag = Tag(name: "Sprint")
        meeting.tags.append(tag)
        XCTAssertEqual(meeting.tags.count, 1)
    }
}
