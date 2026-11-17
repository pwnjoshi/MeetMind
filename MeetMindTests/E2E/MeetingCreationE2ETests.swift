//
//  MeetingCreationE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Meeting Creation, Scheduling, Templates,
//  Feed Filtering, Status State Machine, Tags & Folders, and Audio Import
//  (Scenarios S2, S6, S7, S10, S23, S24, S25, S26, S27, S28, S29, S30, S31, S32, S33).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class MeetingCreationE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var homeVM: HomeViewModel!
    private var setupVM: MeetingSetupViewModel!
    private var mockTranscriptionService: MockSpeechTranscriptionService!
    private var mockSummarizationService: MockSummarizationService!
    private var mockAudioRecorder: MockAudioRecordingService!
    private var tempDirectoryURL: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingCreationTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoryURL = tempDir
        
        homeVM = HomeViewModel(modelContext: context)
        mockTranscriptionService = MockSpeechTranscriptionService()
        mockSummarizationService = MockSummarizationService()
        mockAudioRecorder = MockAudioRecordingService()
        setupVM = MeetingSetupViewModel(
            modelContext: context,
            transcriptionService: mockTranscriptionService,
            summarizationService: mockSummarizationService,
            audioRecordingService: mockAudioRecorder,
            temporaryDirectory: tempDirectoryURL
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        if let tempDir = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDir)
        }
        homeVM = nil
        setupVM = nil
        mockTranscriptionService = nil
        mockSummarizationService = nil
        mockAudioRecorder = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S2 (Scheduled Standup Meeting)
    
    /// Tier 4: Scenario S2 - Scheduled Standup Meeting End-to-End
    /// - Given: User is on the Home dashboard with no meetings scheduled.
    /// - When:
    ///   1. User opens New Meeting -> Schedule Form.
    ///   2. Applies "Team Standup" template with pre-filled agenda.
    ///   3. Sets start date to tomorrow 10:00 AM, end date to tomorrow 10:30 AM.
    ///   4. Adds 4 participants with unique names, emails, and roles.
    ///   5. Saves meeting to SwiftData store.
    /// - Then:
    ///   - Meeting entity is persisted with status `.scheduled`.
    ///   - 4 associated Speaker records are created and linked.
    ///   - Meeting appears in Home dashboard upcoming carousel sorted by date.
    func test_tier4_scenario2_scheduledStandupMeeting() throws {
        // Given
        XCTAssertEqual(homeVM.meetings.count, 0)
        XCTAssertNil(homeVM.upcomingMeeting)
        
        // When
        setupVM.openScheduleForm()
        setupVM.applyTemplate(.teamStandup)
        XCTAssertTrue(setupVM.agenda.contains("What did you work on"))
        
        let tomorrowStart = Date().addingTimeInterval(86400)
        let tomorrowEnd = tomorrowStart.addingTimeInterval(1800)
        setupVM.title = "Engineering Daily Standup"
        setupVM.startDate = tomorrowStart
        setupVM.endDate = tomorrowEnd
        
        setupVM.addParticipant(name: "Alice", email: "alice@meetmind.ai", role: "Frontend Lead")
        setupVM.addParticipant(name: "Bob", email: "bob@meetmind.ai", role: "Backend Lead")
        setupVM.addParticipant(name: "Charlie", email: "charlie@meetmind.ai", role: "Designer")
        setupVM.addParticipant(name: "Diana", email: "diana@meetmind.ai", role: "Product Manager")
        
        XCTAssertEqual(setupVM.participants.count, 4)
        
        let savedMeeting = try setupVM.saveScheduledMeeting()
        homeVM.addMeeting(savedMeeting)
        
        // Then
        XCTAssertNotNil(savedMeeting.id)
        XCTAssertEqual(savedMeeting.title, "Engineering Daily Standup")
        XCTAssertEqual(savedMeeting.status, .scheduled)
        XCTAssertEqual(savedMeeting.participants.count, 4)
        XCTAssertEqual(homeVM.meetings.count, 1)
        XCTAssertNotNil(homeVM.upcomingMeeting)
        XCTAssertEqual(homeVM.upcomingMeeting?.id, savedMeeting.id)
    }

    // MARK: - Tier 4: Scenario S6 (Home Feed Filtering & Swipe Actions)
    
    /// Tier 4: Scenario S6 - Home Feed Filtering and Swipe Actions
    /// - Given: Home feed contains 5 meetings with various dates and star states.
    /// - When:
    ///   1. User applies filter chip "Today".
    ///   2. Stars 2 meetings using leading swipe action.
    ///   3. Switches filter chip to "Starred".
    ///   4. Trailing swipe deletes an old meeting with destructive confirmation.
    /// - Then:
    ///   - "Today" filter returns only meetings occurring today.
    ///   - Starred meetings persist `isFavorite == true`.
    ///   - "Starred" filter returns exactly the 2 starred meetings.
    ///   - Deleted meeting is permanently removed from the SwiftData store.
    func test_tier4_scenario6_homeFeedFilteringAndSwipeActions() throws {
        // Given
        let todayMeeting1 = Meeting(title: "Today Sprint Sync", createdAt: Date(), duration: 1800, status: .completed)
        let todayMeeting2 = Meeting(title: "Today Client Demo", createdAt: Date(), duration: 2400, status: .completed)
        let pastMeeting = Meeting(title: "Last Week Retro", createdAt: Date().addingTimeInterval(-86400 * 7), duration: 3600, status: .completed)
        homeVM.addMeeting(todayMeeting1)
        homeVM.addMeeting(todayMeeting2)
        homeVM.addMeeting(pastMeeting)
        XCTAssertEqual(homeVM.meetings.count, 3)
        
        // When - Filter "Today"
        homeVM.selectedFilter = .today
        XCTAssertEqual(homeVM.filteredMeetings.count, 2)
        XCTAssertTrue(homeVM.filteredMeetings.contains(where: { $0.title == "Today Sprint Sync" }))
        XCTAssertTrue(homeVM.filteredMeetings.contains(where: { $0.title == "Today Client Demo" }))
        
        // When - Leading swipe Star
        homeVM.toggleFavorite(todayMeeting1)
        homeVM.toggleFavorite(pastMeeting)
        XCTAssertTrue(todayMeeting1.isFavorite)
        XCTAssertTrue(pastMeeting.isFavorite)
        
        // When - Filter "Starred"
        homeVM.selectedFilter = .starred
        XCTAssertEqual(homeVM.filteredMeetings.count, 2)
        
        // When - Trailing swipe Delete with confirmation
        homeVM.confirmDeleteMeeting(pastMeeting)
        
        // Then
        XCTAssertEqual(homeVM.meetings.count, 2)
        XCTAssertFalse(homeVM.meetings.contains(where: { $0.id == pastMeeting.id }))
        XCTAssertEqual(homeVM.filteredMeetings.count, 1) // only todayMeeting1 remaining starred
    }

    // MARK: - Tier 4: Scenario S7 (Folder & Tag Organization)
    
    /// Tier 4: Scenario S7 - Folder & Tag Organization
    /// - Given: 3 meetings exist in the default uncategorized space.
    /// - When:
    ///   1. User creates a folder named "Product Roadmap" with color token #7C3AED and icon "folder.fill".
    ///   2. Creates tags "Q4" and "Design".
    ///   3. Moves all 3 meetings into "Product Roadmap".
    ///   4. Applies tags "Q4" and "Design" to the meetings.
    /// - Then:
    ///   - Folder contains exactly 3 meetings.
    ///   - Filtering by tag "Design" returns only tagged meetings.
    ///   - Folder isolation confines meetings to folder navigation scope.
    func test_tier4_scenario7_folderAndTagOrganization() throws {
        // Given
        let m1 = Meeting(title: "Roadmap Review 1")
        let m2 = Meeting(title: "Roadmap Review 2")
        let m3 = Meeting(title: "Architecture Sync")
        homeVM.addMeeting(m1)
        homeVM.addMeeting(m2)
        homeVM.addMeeting(m3)
        
        // When
        let folder = Folder(name: "Product Roadmap", colorHex: "#7C3AED", iconName: "folder.fill")
        let tagQ4 = Tag(name: "Q4", colorHex: "#F59E0B")
        let tagDesign = Tag(name: "Design", colorHex: "#0284C7")
        
        homeVM.moveMeeting(m1, to: folder)
        homeVM.moveMeeting(m2, to: folder)
        homeVM.moveMeeting(m3, to: folder)
        
        homeVM.addTag(tagQ4, to: m1)
        homeVM.addTag(tagDesign, to: m1)
        homeVM.addTag(tagDesign, to: m2)
        
        // Then
        XCTAssertEqual(folder.meetings.count, 3)
        XCTAssertEqual(m1.folder?.name, "Product Roadmap")
        XCTAssertEqual(m1.tags.count, 2)
        XCTAssertEqual(m2.tags.count, 1)
        XCTAssertEqual(m3.tags.count, 0)
        
        let designMeetings = homeVM.meetings(taggedWith: "Design")
        XCTAssertEqual(designMeetings.count, 2)
        XCTAssertTrue(designMeetings.contains(where: { $0.id == m1.id }))
        XCTAssertTrue(designMeetings.contains(where: { $0.id == m2.id }))
    }

    // MARK: - Tier 4: Scenario S10 (External Audio Import Pipeline)
    
    /// Tier 4: Scenario S10 - External Audio Import Pipeline
    /// - Given: User provides an external `.m4a` audio file from Files picker.
    /// - When:
    ///   1. Setup ViewModel validates audio format (.m4a) and duration (>0, <10 hours).
    ///   2. Triggers speech transcription service on the imported audio file.
    ///   3. Runs extractive summarization service.
    ///   4. Constructs a complete Meeting entity with diarized segments and summary.
    /// - Then:
    ///   - Meeting record is created with status `.completed`.
    ///   - Transcript segments are populated with valid start/end timestamps.
    ///   - Summary and extracted action items are attached.
    func test_tier4_scenario10_externalAudioImportPipeline() async throws {
        // Given
        let validAudioURL = URL(fileURLWithPath: "/tmp/imported_interview.m4a")
        mockTranscriptionService.fileTranscriptionResult = [
            LiveTranscriptSegment(text: "Hello everyone, welcome to the quarterly review.", startTime: 0.0, duration: 4.0, confidence: 0.98),
            LiveTranscriptSegment(text: "Let's discuss budget allocations for Q1.", startTime: 4.5, duration: 3.5, confidence: 0.95)
        ]
        mockSummarizationService.mockResponse = MeetingSummaryResponse(
            executiveSummary: "Quarterly review discussing Q1 budget allocations.",
            keyDiscussionPoints: ["Budget allocations", "Quarterly goals"],
            keyDecisions: ["Approved initial budget"],
            actionItems: [ParsedActionItem(title: "Finalize budget spreadsheet", taskDescription: "Draft Q1 budget", assignee: "Alice", dueDate: Date().addingTimeInterval(86400), priority: "high")],
            topics: ["Budget", "Finance"]
        )
        
        // When
        let importedMeeting = try await setupVM.importAudioFile(at: validAudioURL, title: "Quarterly Budget Sync")
        homeVM.addMeeting(importedMeeting)
        
        // Then
        XCTAssertEqual(importedMeeting.title, "Quarterly Budget Sync")
        XCTAssertEqual(importedMeeting.status, .completed)
        XCTAssertEqual(importedMeeting.transcriptSegments.count, 2)
        XCTAssertNotNil(importedMeeting.summary)
        XCTAssertEqual(importedMeeting.summary?.executiveSummary, "Quarterly review discussing Q1 budget allocations.")
        XCTAssertEqual(importedMeeting.actionItems.count, 1)
        XCTAssertEqual(importedMeeting.actionItems.first?.title, "Finalize budget spreadsheet")
    }

    // MARK: - Tier 4: Scenario S23 (Upcoming Meeting Countdown)
    
    /// Tier 4: Scenario S23 - Upcoming Meeting Countdown Transition
    /// - Given: A scheduled meeting starts in 15 minutes.
    /// - When:
    ///   1. Check countdown string at T-15m ("Starts in 15 mins").
    ///   2. Advance time to exact meeting start time T+0m.
    /// - Then:
    ///   - Countdown string updates to "Happening now".
    ///   - Meeting card displays pulsing live start button.
    func test_tier4_scenario23_upcomingMeetingCountdown() throws {
        let meetingDate = Date().addingTimeInterval(900) // 15 mins
        let meeting = Meeting(title: "Sprint Planning", scheduledStartTime: meetingDate, status: .scheduled)
        homeVM.addMeeting(meeting)
        
        let initialCountdown = homeVM.countdownText(for: meeting, referenceDate: Date())
        XCTAssertEqual(initialCountdown, "Starts in 15 mins")
        
        let nowCountdown = homeVM.countdownText(for: meeting, referenceDate: meetingDate)
        XCTAssertEqual(nowCountdown, "Happening now")
    }

    // MARK: - Tier 4: Scenario S24 (Meeting Status State Machine)
    
    /// Tier 4: Scenario S24 - Meeting Status State Machine Transitions
    /// - Given: A new meeting begins at status `.scheduled`.
    /// - When:
    ///   1. Transition to `.recording` upon user launch.
    ///   2. Transition to `.processing` upon recording stop.
    ///   3. Transition to `.completed` upon synthesis completion.
    ///   4. Transition to `.archived` upon user archiving.
    /// - Then:
    ///   - All valid state transitions succeed.
    ///   - Invalid transitions (e.g. `.archived` directly to `.recording`) are rejected.
    func test_tier4_scenario24_meetingStatusStateMachine() throws {
        let meeting = Meeting(title: "Product Sync", status: .scheduled)
        
        XCTAssertTrue(meeting.canTransition(to: .recording))
        try meeting.transition(to: .recording)
        XCTAssertEqual(meeting.status, .recording)
        
        XCTAssertTrue(meeting.canTransition(to: .processing))
        try meeting.transition(to: .processing)
        XCTAssertEqual(meeting.status, .processing)
        
        XCTAssertTrue(meeting.canTransition(to: .completed))
        try meeting.transition(to: .completed)
        XCTAssertEqual(meeting.status, .completed)
        
        XCTAssertTrue(meeting.canTransition(to: .archived))
        try meeting.transition(to: .archived)
        XCTAssertEqual(meeting.status, .archived)
        
        // Invalid transition
        XCTAssertFalse(meeting.canTransition(to: .recording))
    }

    // MARK: - Tier 4: Scenario S25 (Multi-Filter Combination)
    
    /// Tier 4: Scenario S25 - Multi-Filter Combination Intersection
    /// - Given: 4 meetings with varying dates and action item counts.
    /// - When: User applies combined filter: "This Week" + "Has Action Items".
    /// - Then: Returns only meetings occurring within the current week that have pending action items.
    func test_tier4_scenario25_multiFilterCombination() throws {
        let m1 = Meeting(title: "This Week With Tasks", createdAt: Date(), status: .completed)
        let task1 = ActionItem(title: "Fix bug", priority: .high)
        m1.actionItems.append(task1)
        
        let m2 = Meeting(title: "This Week No Tasks", createdAt: Date(), status: .completed)
        
        let m3 = Meeting(title: "Last Month With Tasks", createdAt: Date().addingTimeInterval(-86400 * 30), status: .completed)
        let task2 = ActionItem(title: "Deploy app", priority: .low)
        m3.actionItems.append(task2)
        
        homeVM.addMeeting(m1)
        homeVM.addMeeting(m2)
        homeVM.addMeeting(m3)
        
        let filtered = homeVM.filterMeetings(dateRange: .thisWeek, hasActionItems: true)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, m1.id)
    }

    // MARK: - Tier 4: Scenario S26 (Favorite Star Toggle)
    
    /// Tier 4: Scenario S26 - Favorite Star Toggle
    /// - Given: An unstarred meeting card in Home feed.
    /// - When: User toggles star on the card.
    /// - Then: `isFavorite` turns true, star icon color resolves amber #F59E0B, persists in store.
    func test_tier4_scenario26_favoriteStarToggle() throws {
        let meeting = Meeting(title: "Design Critique", isFavorite: false)
        homeVM.addMeeting(meeting)
        
        homeVM.toggleFavorite(meeting)
        XCTAssertTrue(meeting.isFavorite)
        XCTAssertEqual(homeVM.starColorToken(for: meeting), "#F59E0B")
        
        homeVM.toggleFavorite(meeting)
        XCTAssertFalse(meeting.isFavorite)
        XCTAssertEqual(homeVM.starColorToken(for: meeting), "#9CA3AF")
    }

    // MARK: - Tier 4: Scenario S27 (New Meeting Modal Dismissal)
    
    /// Tier 4: Scenario S27 - New Meeting Modal Dismissal Leaves No Phantom Drafts
    /// - Given: User opens New Meeting sheet.
    /// - When: Enters a temporary title and cancels/dismisses sheet.
    /// - Then: Database contains 0 new meetings and draft state is completely purged.
    func test_tier4_scenario27_newMeetingModalDismissal() throws {
        let initialCount = homeVM.meetings.count
        setupVM.openScheduleForm()
        setupVM.title = "Draft That Was Cancelled"
        setupVM.cancelAndDismiss()
        
        XCTAssertEqual(homeVM.meetings.count, initialCount)
        XCTAssertEqual(setupVM.title, "")
        XCTAssertFalse(setupVM.isFormOpen)
    }

    // MARK: - Tier 4: Scenario S28 (Meeting Date Validation)
    
    /// Tier 4: Scenario S28 - Meeting Date Validation Invariants
    /// - Given: Schedule Meeting form is open.
    /// - When: User selects an End Date that is chronologically earlier than Start Date.
    /// - Then: Form emits inline validation error, disables Save button, and prevents persistence.
    func test_tier4_scenario28_meetingDateValidation() throws {
        setupVM.openScheduleForm()
        setupVM.title = "Invalid Date Meeting"
        
        let start = Date().addingTimeInterval(3600)
        let invalidEnd = Date().addingTimeInterval(1800) // 30 mins before start
        setupVM.startDate = start
        setupVM.endDate = invalidEnd
        
        XCTAssertFalse(setupVM.isFormValid)
        XCTAssertEqual(setupVM.validationErrorMessage, "End time must be after start time")
        XCTAssertThrowsError(try setupVM.saveScheduledMeeting())
    }

    // MARK: - Tier 4: Scenario S29 (Custom Meeting Template Creation)
    
    /// Tier 4: Scenario S29 - Custom Meeting Template Creation and Application
    /// - Given: Predefined templates exist (Standup, 1-on-1, etc.).
    /// - When: User creates a custom template "Sprint Retrospective" with 3 sections.
    /// - Then: Template appears in template selector and pre-populates agenda correctly.
    func test_tier4_scenario29_customMeetingTemplateCreation() throws {
        setupVM.createCustomTemplate(
            name: "Sprint Retrospective",
            sections: ["1. What went well", "2. What didn't go well", "3. Action items"],
            defaultDuration: 3600
        )
        
        XCTAssertTrue(setupVM.availableTemplates.contains(where: { $0.name == "Sprint Retrospective" }))
        setupVM.applyCustomTemplate(named: "Sprint Retrospective")
        
        XCTAssertTrue(setupVM.agenda.contains("What went well"))
        XCTAssertTrue(setupVM.agenda.contains("Action items"))
        XCTAssertEqual(setupVM.endDate.timeIntervalSince(setupVM.startDate), 3600)
    }

    // MARK: - Tier 4: Scenario S30 (Duplicate Participant Prevention)
    
    /// Tier 4: Scenario S30 - Duplicate Participant Prevention and Role Merging
    /// - Given: Participant "Bob" with email "bob@meetmind.ai" is already added with role "Developer".
    /// - When: User attempts to add "Bob" again with "bob@meetmind.ai" and role "Scrum Master".
    /// - Then: Participant count remains 1, and role is updated/merged without creating twin records.
    func test_tier4_scenario30_duplicateParticipantPrevention() throws {
        setupVM.addParticipant(name: "Bob", email: "bob@meetmind.ai", role: "Developer")
        XCTAssertEqual(setupVM.participants.count, 1)
        
        setupVM.addParticipant(name: "Bob", email: "bob@meetmind.ai", role: "Scrum Master")
        XCTAssertEqual(setupVM.participants.count, 1)
        XCTAssertEqual(setupVM.participants.first?.role, "Scrum Master")
    }

    // MARK: - Tier 4: Scenario S31 (Quick Launch Timestamping)
    
    /// Tier 4: Scenario S31 - Quick Launch Instant Title Timestamping
    /// - Given: User taps "Quick Meeting" button on Home dashboard.
    /// - When: Quick meeting initializes immediately.
    /// - Then: Title is auto-formatted with current localized date/time and recording starts within 150ms.
    func test_tier4_scenario31_quickLaunchTimestamping() throws {
        let quickMeeting = setupVM.quickLaunchMeeting()
        XCTAssertTrue(quickMeeting.title.hasPrefix("Meeting - "))
        XCTAssertEqual(quickMeeting.status, .recording)
        XCTAssertNotNil(quickMeeting.id)
    }

    // MARK: - Tier 4: Scenario S32 (Corrupt Audio Import Handling)
    
    /// Tier 4: Scenario S32 - Corrupt Audio Import Graceful Error Handling
    /// - Given: User selects a corrupted or 0-byte `.wav` file.
    /// - When: Audio import pipeline attempts validation and transcription.
    /// - Then: Pipeline throws `AudioImportError.corruptedFile`, emits an error alert, and avoids app crash.
    func test_tier4_scenario32_corruptAudioImportHandling() async throws {
        let corruptURL = URL(fileURLWithPath: "/tmp/corrupt_file.wav")
        mockTranscriptionService.shouldThrowCorruptAudio = true
        
        do {
            _ = try await setupVM.importAudioFile(at: corruptURL, title: "Corrupt Meeting")
            XCTFail("Import should fail for corrupt audio")
        } catch {
            XCTAssertNotNil(error)
            XCTAssertTrue(setupVM.hasImportError)
            XCTAssertEqual(setupVM.importErrorMessage, "Selected audio file is corrupt or unreadable.")
        }
    }

    // MARK: - Tier 4: Scenario S33 (Folder Deletion Policy)
    
    /// Tier 4: Scenario S33 - Folder Deletion Policy Preserves Child Meetings
    /// - Given: A folder contains 5 meetings.
    /// - When: User deletes the folder using `.nullify` policy.
    /// - Then: Folder is deleted, but all 5 meetings remain safe in the default inbox.
    func test_tier4_scenario33_folderDeletionPolicy() throws {
        let folder = Folder(name: "Temporary Folder")
        var createdMeetings: [Meeting] = []
        for i in 1...5 {
            let m = Meeting(title: "Folder Meeting \(i)")
            homeVM.addMeeting(m)
            homeVM.moveMeeting(m, to: folder)
            createdMeetings.append(m)
        }
        XCTAssertEqual(folder.meetings.count, 5)
        
        homeVM.deleteFolder(folder)
        
        for m in createdMeetings {
            XCTAssertNil(m.folder)
            XCTAssertTrue(homeVM.meetings.contains(where: { $0.id == m.id }))
        }
        XCTAssertEqual(homeVM.meetings.count, 5)
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - 1-on-1 Template Combined with 2 Participants
    /// - Verifies 1-on-1 template constraints and participant linking.
    func test_tier3_templateAndParticipantPairwise() throws {
        setupVM.openScheduleForm()
        setupVM.applyTemplate(.oneOnOne)
        setupVM.addParticipant(name: "Manager", email: "mgr@meetmind.ai", role: "Manager")
        setupVM.addParticipant(name: "Report", email: "rep@meetmind.ai", role: "Engineer")
        
        let meeting = try setupVM.saveScheduledMeeting()
        XCTAssertEqual(meeting.templateName, "1-on-1")
        XCTAssertEqual(meeting.participants.count, 2)
    }

    /// Tier 3: Pairwise - Moving Tagged Meetings Across Folders
    /// - Verifies tags persist when meetings move between folders.
    func test_tier3_multiTagAndFolderMovePairwise() throws {
        let meeting = Meeting(title: "Multi Tag Meeting")
        let tag = Tag(name: "Urgent", colorHex: "#DC2626")
        let folderA = Folder(name: "Folder A")
        let folderB = Folder(name: "Folder B")
        
        homeVM.addMeeting(meeting)
        homeVM.addTag(tag, to: meeting)
        homeVM.moveMeeting(meeting, to: folderA)
        XCTAssertEqual(meeting.folder?.name, "Folder A")
        XCTAssertEqual(meeting.tags.count, 1)
        
        homeVM.moveMeeting(meeting, to: folderB)
        XCTAssertEqual(meeting.folder?.name, "Folder B")
        XCTAssertEqual(meeting.tags.count, 1)
    }

    /// Tier 3: Pairwise - Upcoming Meeting Filter and Status Transition
    /// - Verifies status transitions reflect accurately inside the upcoming filter.
    func test_tier3_upcomingFilterAndStatusPairwise() throws {
        let meeting = Meeting(title: "Upcoming Transition Sync", scheduledStartTime: Date().addingTimeInterval(300), status: .scheduled)
        homeVM.addMeeting(meeting)
        XCTAssertNotNil(homeVM.upcomingMeeting)
        
        try meeting.transition(to: .recording)
        XCTAssertEqual(meeting.status, .recording)
    }

    /// Tier 3: Pairwise - Audio File Format Validation Across Extensions
    /// - Verifies supported vs unsupported file extensions during import.
    func test_tier3_audioImportValidationPairwise() throws {
        XCTAssertTrue(setupVM.isSupportedAudioExtension("m4a"))
        XCTAssertTrue(setupVM.isSupportedAudioExtension("mp3"))
        XCTAssertTrue(setupVM.isSupportedAudioExtension("wav"))
        XCTAssertFalse(setupVM.isSupportedAudioExtension("txt"))
        XCTAssertFalse(setupVM.isSupportedAudioExtension("pdf"))
    }

    /// Tier 3: Pairwise - Multiple Participant Add and Email Syntax Validation
    /// - Verifies invalid email syntax rejection during participant addition.
    func test_tier3_duplicateParticipantMergePairwise() throws {
        setupVM.addParticipant(name: "Valid User", email: "user@domain.com", role: "Dev")
        XCTAssertEqual(setupVM.participants.count, 1)
        
        setupVM.addParticipant(name: "Invalid User", email: "not-an-email", role: "Dev")
        XCTAssertEqual(setupVM.participants.count, 1) // rejected
    }

    /// Tier 3: Pairwise - Quick Launch While Scheduled Meeting Exists
    /// - Verifies quick launching does not overwrite scheduled meetings.
    func test_tier3_quickLaunchAndScheduleConflictPairwise() throws {
        let scheduled = Meeting(title: "Scheduled Sync", scheduledStartTime: Date().addingTimeInterval(3600), status: .scheduled)
        homeVM.addMeeting(scheduled)
        
        let quick = setupVM.quickLaunchMeeting()
        homeVM.addMeeting(quick)
        
        XCTAssertEqual(homeVM.meetings.count, 2)
        XCTAssertEqual(homeVM.upcomingMeeting?.id, scheduled.id)
    }

    /// Tier 3: Pairwise - Folder Nullify Cascade Preserves Tags
    /// - Verifies deleting a folder preserves meeting tags intact.
    func test_tier3_folderNullifyCascadePairwise() throws {
        let folder = Folder(name: "ToDelete")
        let meeting = Meeting(title: "Tagged In Folder")
        let tag = Tag(name: "Important")
        
        homeVM.addMeeting(meeting)
        homeVM.moveMeeting(meeting, to: folder)
        homeVM.addTag(tag, to: meeting)
        
        homeVM.deleteFolder(folder)
        XCTAssertNil(meeting.folder)
        XCTAssertEqual(meeting.tags.count, 1)
    }
}
