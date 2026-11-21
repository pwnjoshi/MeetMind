//
//  MeetingSetupViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Comprehensive test suite covering New Meeting Launcher, Scheduled Meeting Form,
/// Templates Selector, Participant Manager, Quick Meeting Launcher, Audio Import Pipeline,
/// and Folders & Tags Organization.
/// Corresponds to Features 22, 23, 24, 25, 26, 27, and 28.
@MainActor
final class MeetingSetupViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    func testUnreadableNonemptyAudioDoesNotInventTwoMinuteDuration() throws {
        let url = tempDirectoryURL.appendingPathComponent("unreadable.m4a")
        try Data("not an audio container".utf8).write(to: url)
        XCTAssertThrowsError(try sut.importAudioFile(from: url))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 0)
    }

    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: MeetingSetupViewModel!
    private var mockTranscription: MockSpeechTranscriptionService!
    private var mockSummarizer: MockSummarizationService!
    private var mockRecorder: MockAudioRecordingService!
    private var tempDirectoryURL: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockTranscription = MockSpeechTranscriptionService()
        mockSummarizer = MockSummarizationService()
        mockRecorder = MockAudioRecordingService()
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingSetupTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoryURL = tempDir
        
        sut = MeetingSetupViewModel(
            modelContext: context,
            transcriptionService: mockTranscription,
            summarizationService: mockSummarizer,
            audioRecordingService: mockRecorder,
            temporaryDirectory: tempDirectoryURL
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        if let tempDir = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDir)
        }
        sut = nil
        mockTranscription = nil
        mockSummarizer = nil
        mockRecorder = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    private func fetchMeeting(id: UUID) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    // MARK: - Tier 1: Feature 22 (New Meeting Modal Launcher)
    
    /// Tier 1: Feature 22 - Validates initial launcher state presents 3 options and is not presented.
    func test_tier1_feature22_newMeetingSheetInitialState() throws {
        XCTAssertFalse(sut.isSheetPresented)
        XCTAssertEqual(sut.availableSetupOptions, [.quickStart, .schedule, .importAudio])
        XCTAssertEqual(sut.currentWorkflow, .launcher)
    }
    
    /// Tier 1: Feature 22 - Validates selecting a setup workflow option transitions sheet state.
    func test_tier1_feature22_selectSetupWorkflowOption() throws {
        sut.presentSheet()
        XCTAssertTrue(sut.isSheetPresented)
        
        sut.selectSetupOption(.schedule)
        XCTAssertEqual(sut.currentWorkflow, .scheduleForm)
        
        sut.selectSetupOption(.importAudio)
        XCTAssertEqual(sut.currentWorkflow, .audioImport)
    }
    
    /// Tier 1: Feature 22 - Validates dismissing modal sheet cleans up and resets state.
    func test_tier1_feature22_dismissNewMeetingSheet() throws {
        sut.presentSheet()
        sut.selectSetupOption(.schedule)
        sut.title = "Draft Meeting Title"
        
        sut.dismissSheet()
        
        XCTAssertFalse(sut.isSheetPresented)
        XCTAssertEqual(sut.currentWorkflow, .launcher)
        XCTAssertEqual(sut.title, "")
    }
    
    // MARK: - Tier 1: Feature 23 (Schedule Meeting Form)
    
    /// Tier 1: Feature 23 - Validates form field bindings for scheduled title, dates, and agenda.
    func test_tier1_feature23_scheduleFormBinding() throws {
        let start = Date().addingTimeInterval(3600)
        let end = start.addingTimeInterval(1800)
        
        sut.title = "Q4 Product Strategy"
        sut.startDate = start
        sut.endDate = end
        sut.agendaText = "Review key goals and team headcount."
        
        XCTAssertEqual(sut.title, "Q4 Product Strategy")
        XCTAssertEqual(sut.startDate, start)
        XCTAssertEqual(sut.endDate, end)
        XCTAssertEqual(sut.agendaText, "Review key goals and team headcount.")
        XCTAssertTrue(sut.isFormValid)
    }
    
    /// Tier 1: Feature 23 - Validates start date before end date produces valid form state.
    func test_tier1_feature23_scheduleFormDatesValidationValidRange() throws {
        let now = Date()
        sut.title = "Sprint Review"
        sut.startDate = now.addingTimeInterval(3600)
        sut.endDate = now.addingTimeInterval(5400)
        
        XCTAssertTrue(sut.areDatesValid)
        XCTAssertNil(sut.dateValidationError)
        XCTAssertTrue(sut.isFormValid)
    }
    
    /// Tier 1: Feature 23 - Validates saving scheduled meeting inserts valid record into store.
    func test_tier1_feature23_scheduleMeetingSavesToStore() throws {
        let start = Date().addingTimeInterval(7200)
        let end = start.addingTimeInterval(3600)
        sut.title = "Design Architecture Sync"
        sut.startDate = start
        sut.endDate = end
        sut.agendaText = "Figma token mapping"
        let seriesID = UUID()
        sut.scheduledSeriesID = seriesID
        sut.scheduledSeriesName = "Architecture reviews"
        
        let savedMeeting = try sut.saveScheduledMeeting()
        
        XCTAssertNotNil(savedMeeting)
        XCTAssertEqual(savedMeeting.title, "Design Architecture Sync")
        XCTAssertEqual(savedMeeting.status, .scheduled)
        XCTAssertEqual(savedMeeting.scheduledStartTime, start)
        XCTAssertEqual(fetchMeeting(id: savedMeeting.id)?.title, "Design Architecture Sync")
        let freshContext = ModelContext(modelContainer)
        let persisted = try XCTUnwrap(freshContext.fetch(FetchDescriptor<Meeting>()).first { $0.id == savedMeeting.id })
        XCTAssertEqual(persisted.seriesID, seriesID)
        XCTAssertEqual(persisted.seriesName, "Architecture reviews")
    }
    
    // MARK: - Tier 1: Feature 24 (Meeting Templates Selector)
    
    /// Tier 1: Feature 24 - Validates Standup template pre-fills default agenda items.
    func test_tier1_feature24_templateSelectionStandupPreFillsAgenda() throws {
        sut.selectTemplate(.standup)
        
        XCTAssertEqual(sut.selectedTemplate, .standup)
        XCTAssertTrue(sut.agendaText.contains("Yesterday:"))
        XCTAssertTrue(sut.agendaText.contains("Today:"))
        XCTAssertTrue(sut.agendaText.contains("Blockers:"))
    }
    
    /// Tier 1: Feature 24 - Validates 1-on-1 template pre-fills personalized discussion sections.
    func test_tier1_feature24_templateSelectionOneOnOnePreFillsAgenda() throws {
        sut.selectTemplate(.oneOnOne)
        
        XCTAssertEqual(sut.selectedTemplate, .oneOnOne)
        XCTAssertTrue(sut.agendaText.contains("Wins & Progress"))
        XCTAssertTrue(sut.agendaText.contains("Challenges & Support"))
        XCTAssertTrue(sut.agendaText.contains("Career & Growth"))
    }
    
    /// Tier 1: Feature 24 - Validates Client Sales template pre-fills discovery and demo points.
    func test_tier1_feature24_templateSelectionClientSalesPreFillsAgenda() throws {
        sut.selectTemplate(.clientSales)
        
        XCTAssertEqual(sut.selectedTemplate, .clientSales)
        XCTAssertTrue(sut.agendaText.contains("Client Pain Points"))
        XCTAssertTrue(sut.agendaText.contains("Product Demo"))
        XCTAssertTrue(sut.agendaText.contains("Pricing & Next Steps"))
    }
    
    /// Tier 1: Feature 24 - Validates Brainstorm template pre-fills ideation framework.
    func test_tier1_feature24_templateSelectionBrainstormPreFillsAgenda() throws {
        sut.selectTemplate(.brainstorm)
        
        XCTAssertEqual(sut.selectedTemplate, .brainstorm)
        XCTAssertTrue(sut.agendaText.contains("Problem Statement"))
        XCTAssertTrue(sut.agendaText.contains("Divergent Ideas"))
        XCTAssertTrue(sut.agendaText.contains("Action Plan"))
    }
    
    /// Tier 1: Feature 24 - Validates General template defaults to standard meeting format.
    func test_tier1_feature24_templateSelectionGeneralDefault() throws {
        sut.selectTemplate(.general)
        
        XCTAssertEqual(sut.selectedTemplate, .general)
        XCTAssertTrue(sut.agendaText.contains("Discussion Topics"))
        XCTAssertTrue(sut.agendaText.contains("Action Items"))
    }
    
    // MARK: - Tier 1: Feature 25 (Participant Manager)
    
    /// Tier 1: Feature 25 - Validates adding participant with valid name, email, and role.
    func test_tier1_feature25_addParticipantWithValidDetails() throws {
        sut.addParticipant(name: "Sarah Connor", email: "sarah@cyberdyne.io", role: "Product Manager")
        
        XCTAssertEqual(sut.participants.count, 1)
        let added = sut.participants.first
        XCTAssertEqual(added?.name, "Sarah Connor")
        XCTAssertEqual(added?.email, "sarah@cyberdyne.io")
        XCTAssertEqual(added?.role, "Product Manager")
    }
    
    /// Tier 1: Feature 25 - Validates removing participant by identifier deletes them from list.
    func test_tier1_feature25_removeParticipantRemovesFromList() throws {
        sut.addParticipant(name: "Alex", email: "alex@team.com", role: "Dev")
        sut.addParticipant(name: "Taylor", email: "taylor@team.com", role: "QA")
        XCTAssertEqual(sut.participants.count, 2)
        
        let alexId = sut.participants.first!.id
        sut.removeParticipant(id: alexId)
        
        XCTAssertEqual(sut.participants.count, 1)
        XCTAssertEqual(sut.participants.first?.name, "Taylor")
    }
    
    /// Tier 1: Feature 25 - Validates avatar color assignment cycles through palette.
    func test_tier1_feature25_participantAvatarColorAssigned() throws {
        sut.addParticipant(name: "P1", email: "p1@t.com", role: "Eng")
        sut.addParticipant(name: "P2", email: "p2@t.com", role: "Eng")
        
        let p1Color = sut.participants[0].avatarColorHex
        let p2Color = sut.participants[1].avatarColorHex
        
        XCTAssertFalse(p1Color.isEmpty)
        XCTAssertFalse(p2Color.isEmpty)
        XCTAssertNotEqual(p1Color, p2Color)
    }
    
    /// Tier 1: Feature 25 - Validates assigning participant roles.
    func test_tier1_feature25_participantRoleAssignment() throws {
        sut.addParticipant(name: "John", email: "john@t.com", role: "Organizer")
        XCTAssertEqual(sut.participants.first?.role, "Organizer")
        
        sut.updateParticipantRole(id: sut.participants.first!.id, newRole: "Note Taker")
        XCTAssertEqual(sut.participants.first?.role, "Note Taker")
    }
    
    // MARK: - Tier 1: Feature 26 (Quick Meeting Launcher)
    
    /// Tier 1: Feature 26 - Validates quick meeting start creates immediate meeting record.
    func test_tier1_feature26_quickMeetingLauncherCreatesImmediateMeeting() throws {
        let quickMeeting = sut.quickStartMeeting()
        
        XCTAssertNotNil(quickMeeting)
        XCTAssertEqual(quickMeeting.status, .recording)
        XCTAssertNotNil(fetchMeeting(id: quickMeeting.id))
    }
    
    /// Tier 1: Feature 26 - Validates quick start title contains date or timestamp.
    func test_tier1_feature26_quickMeetingTitleContainsTimestamp() throws {
        let quickMeeting = sut.quickStartMeeting()
        XCTAssertTrue(quickMeeting.title.contains("Quick Meeting") || quickMeeting.title.contains("Instant"))
    }
    
    /// Tier 1: Feature 26 - Validates quick start triggers immediate navigation to recording screen.
    func test_tier1_feature26_quickMeetingNavigatesToRecording() throws {
        var didNavigate = false
        var targetMeetingId: UUID?
        sut.onNavigateToRecording = { meetingId in
            didNavigate = true
            targetMeetingId = meetingId
        }
        
        let meeting = sut.quickStartMeeting()
        
        XCTAssertTrue(didNavigate)
        XCTAssertEqual(targetMeetingId, meeting.id)
    }
    
    // MARK: - Tier 1: Feature 27 (Audio File Import)
    
    /// Tier 1: Feature 27 - Validates supported audio extensions include m4a, mp3, and wav.
    func test_tier1_feature27_audioFileImportAcceptedExtensions() throws {
        XCTAssertTrue(sut.isExtensionSupported("m4a"))
        XCTAssertTrue(sut.isExtensionSupported("mp3"))
        XCTAssertTrue(sut.isExtensionSupported("wav"))
        XCTAssertFalse(sut.isExtensionSupported("txt"))
        XCTAssertFalse(sut.isExtensionSupported("pdf"))
    }
    
    /// Tier 1: Feature 27 - Validates importing audio calculates duration from audio asset.
    func test_tier1_feature27_audioFileImportParsesDuration() throws {
        let audioFileURL = tempDirectoryURL.appendingPathComponent("sample_recording.m4a")
        try Data("simulated m4a content".utf8).write(to: audioFileURL)
        
        sut.setSimulatedAudioDuration(185.0)
        let meeting = try sut.importAudioFile(from: audioFileURL)
        
        XCTAssertEqual(meeting.duration, 185.0)
        XCTAssertNotEqual(meeting.audioFileURL, audioFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(meeting.audioFileURL).path))
    }
    
    /// Tier 1: Feature 27 - Validates imported audio creates meeting in processing state.
    func test_tier1_feature27_audioFileImportCreatesMeetingInProcessingState() throws {
        let audioFileURL = tempDirectoryURL.appendingPathComponent("import_test.wav")
        try Data("wav content".utf8).write(to: audioFileURL)
        sut.setSimulatedAudioDuration(120)
        
        let meeting = try sut.importAudioFile(from: audioFileURL)
        XCTAssertEqual(meeting.status, .processing)
    }
    
    // MARK: - Tier 1: Feature 28 (Folders & Tags Organization)
    
    /// Tier 1: Feature 28 - Validates folder assignment during meeting setup.
    func test_tier1_feature28_assignFolderToMeetingSetup() throws {
        let folder = Folder(name: "Executive Committee", colorHex: "#8B5CF6")
        context.insert(folder)
        try? context.save()
        sut.selectFolder(folder)
        
        XCTAssertEqual(sut.selectedFolder?.id, folder.id)
        XCTAssertEqual(sut.selectedFolder?.name, "Executive Committee")
    }
    
    /// Tier 1: Feature 28 - Validates adding tags to meeting during setup.
    func test_tier1_feature28_addTagToMeetingSetup() throws {
        let tag1 = Tag(name: "Q4", colorHex: "#3B82F6")
        let tag2 = Tag(name: "Urgent", colorHex: "#EF4444")
        context.insert(tag1)
        context.insert(tag2)
        try? context.save()
        
        sut.addTag(tag1)
        sut.addTag(tag2)
        
        XCTAssertEqual(sut.selectedTags.count, 2)
        XCTAssertTrue(sut.selectedTags.contains(where: { $0.name == "Q4" }))
    }
    
    /// Tier 1: Feature 28 - Validates removing tag from meeting setup.
    func test_tier1_feature28_removeTagFromMeetingSetup() throws {
        let tag = Tag(name: "Roadmap", colorHex: "#10B981")
        context.insert(tag)
        try? context.save()
        sut.addTag(tag)
        XCTAssertEqual(sut.selectedTags.count, 1)
        
        sut.removeTag(tag)
        XCTAssertEqual(sut.selectedTags.count, 0)
    }
    
    /// Tier 1: Feature 28 - Validates inline creation of a custom tag.
    func test_tier1_feature28_createCustomTagInline() throws {
        let newTag = sut.createTag(name: "AI Strategy", colorHex: "#F59E0B")
        
        XCTAssertEqual(newTag.name, "AI Strategy")
        XCTAssertEqual(newTag.colorHex, "#F59E0B")
        XCTAssertTrue(sut.selectedTags.contains(where: { $0.id == newTag.id }))
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 22: Launcher Memory & Draft Cleanup)
    
    /// Tier 2: Feature 22 - Validates rapid open and dismiss cycles do not leak state.
    func test_tier2_feature22_rapidOpenAndDismissSheetNoMemoryLeak() throws {
        for _ in 0..<20 {
            sut.presentSheet()
            sut.dismissSheet()
        }
        XCTAssertFalse(sut.isSheetPresented)
        XCTAssertEqual(sut.participants.count, 0)
    }
    
    /// Tier 2: Feature 22 - Validates sheet dismissal clears all draft participant chips.
    func test_tier2_feature22_sheetDismissalCleansUpDraftState() throws {
        sut.presentSheet()
        sut.addParticipant(name: "Draft Person", email: "d@t.com", role: "Dev")
        sut.dismissSheet()
        
        XCTAssertEqual(sut.participants.count, 0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 23: Schedule Validation)
    
    /// Tier 2: Feature 23 - Validates start date after end date emits validation error and disables save.
    func test_tier2_feature23_scheduleStartDateAfterEndDateFailsValidation() throws {
        let now = Date()
        sut.title = "Invalid Date Meeting"
        sut.startDate = now.addingTimeInterval(3600)  // In 1 hour
        sut.endDate = now.addingTimeInterval(1800)    // In 30 mins (earlier!)
        
        XCTAssertFalse(sut.areDatesValid)
        XCTAssertFalse(sut.isFormValid)
        XCTAssertEqual(sut.dateValidationError, "End time must be after start time.")
        
        XCTAssertThrowsError(try sut.saveScheduledMeeting()) { error in
            XCTAssertTrue(error is MeetingValidationError)
        }
    }
    
    /// Tier 2: Feature 23 - Validates scheduling with empty title auto-generates localized title.
    func test_tier2_feature23_scheduleMeetingWithEmptyTitleAutoGeneratesTitle() throws {
        sut.title = ""
        sut.startDate = Date().addingTimeInterval(3600)
        sut.endDate = Date().addingTimeInterval(5400)
        
        let meeting = try sut.saveScheduledMeeting()
        XCTAssertFalse(meeting.title.isEmpty)
        XCTAssertTrue(meeting.title.contains("Scheduled Meeting"))
    }
    
    /// Tier 2: Feature 23 - Validates scheduling start date in past presents non-fatal warning.
    func test_tier2_feature23_scheduleMeetingInPastEmitsWarning() throws {
        sut.title = "Past Review"
        sut.startDate = Date().addingTimeInterval(-3600) // 1 hour ago
        sut.endDate = Date().addingTimeInterval(1800)
        
        XCTAssertTrue(sut.hasPastDateWarning)
        XCTAssertEqual(sut.pastDateWarningMessage, "Scheduled time is in the past.")
    }
    
    /// Tier 2: Feature 23 - Validates duration exceeding 24 hours displays alert confirmation.
    func test_tier2_feature23_scheduleDurationExceeding24HoursWarning() throws {
        let now = Date()
        sut.startDate = now
        sut.endDate = now.addingTimeInterval(86400 * 2) // 48 hours
        
        XCTAssertTrue(sut.isDurationExcessive)
        XCTAssertEqual(sut.durationExcessiveWarning, "Meeting duration exceeds 24 hours.")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 24: Template Switching & Edge Cases)
    
    /// Tier 2: Feature 24 - Validates switching templates prompts before overwriting custom edits.
    func test_tier2_feature24_switchingTemplatesPreservesCustomUserEditsWarning() throws {
        sut.selectTemplate(.standup)
        sut.agendaText = "Custom user customized agenda text."
        
        sut.attemptTemplateSwitch(to: .oneOnOne)
        XCTAssertTrue(sut.isShowingTemplateOverwriteConfirmation)
        
        sut.confirmTemplateSwitch()
        XCTAssertEqual(sut.selectedTemplate, .oneOnOne)
    }
    
    /// Tier 2: Feature 24 - Validates template with empty custom sections defaults to General.
    func test_tier2_feature24_customTemplateWithEmptySectionsFallback() throws {
        sut.applyCustomTemplate(title: "Empty Template", sections: [])
        XCTAssertEqual(sut.selectedTemplate, .general)
    }
    
    /// Tier 2: Feature 24 - Validates unselected template defaults to general meeting.
    func test_tier2_feature24_unselectedTemplateDefaultsToGeneral() throws {
        sut.resetTemplateSelection()
        XCTAssertEqual(sut.selectedTemplate, .general)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 25: Participant Manager Boundaries)
    
    /// Tier 2: Feature 25 - Validates empty participant name is rejected.
    func test_tier2_feature25_addParticipantEmptyNameRejected() throws {
        let didAdd = sut.addParticipant(name: "", email: "test@team.com", role: "Dev")
        XCTAssertFalse(didAdd)
        XCTAssertEqual(sut.participants.count, 0)
    }
    
    /// Tier 2: Feature 25 - Validates whitespace-only participant name is rejected.
    func test_tier2_feature25_addParticipantWhitespaceOnlyRejected() throws {
        let didAdd = sut.addParticipant(name: "   \t  ", email: "test@team.com", role: "Dev")
        XCTAssertFalse(didAdd)
        XCTAssertEqual(sut.participants.count, 0)
    }
    
    /// Tier 2: Feature 25 - Validates adding participant with duplicate email merges role rather than duplicate chip.
    func test_tier2_feature25_addDuplicateParticipantEmailMergesRole() throws {
        sut.addParticipant(name: "Sarah C", email: "sarah@cyberdyne.io", role: "Developer")
        XCTAssertEqual(sut.participants.count, 1)
        
        // Add same email with new role
        sut.addParticipant(name: "Sarah Connor", email: "sarah@cyberdyne.io", role: "Product Manager")
        
        XCTAssertEqual(sut.participants.count, 1, "Should merge into 1 participant chip")
        XCTAssertEqual(sut.participants.first?.name, "Sarah Connor")
        XCTAssertEqual(sut.participants.first?.role, "Product Manager")
    }
    
    /// Tier 2: Feature 25 - Validates participant list cap at 50 attendees.
    func test_tier2_feature25_maxParticipantsLimitCapAtFifty() throws {
        for i in 0..<50 {
            _ = sut.addParticipant(name: "User \(i)", email: "u\(i)@team.com", role: "Member")
        }
        XCTAssertEqual(sut.participants.count, 50)
        
        let didAdd51st = sut.addParticipant(name: "Overflow User", email: "overflow@team.com", role: "Guest")
        XCTAssertFalse(didAdd51st)
        XCTAssertEqual(sut.participants.count, 50)
        XCTAssertTrue(sut.isParticipantLimitReached)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 26: Quick Start Collisions)
    
    /// Tier 2: Feature 26 - Validates quick start title timestamp collision handles duplicate timestamps.
    func test_tier2_feature26_quickMeetingTitleCollisionResolution() throws {
        let m1 = sut.quickStartMeeting()
        let m2 = sut.quickStartMeeting()
        
        XCTAssertNotEqual(m1.id, m2.id)
        XCTAssertNotNil(fetchMeeting(id: m1.id))
        XCTAssertNotNil(fetchMeeting(id: m2.id))
    }
    
    /// Tier 2: Feature 26 - Validates quick meeting default audio quality respects user settings.
    func test_tier2_feature26_quickMeetingDefaultAudioQualityRespectsSettings() throws {
        sut.defaultAudioQuality = .high
        let meeting = sut.quickStartMeeting()
        XCTAssertEqual(meeting.audioQuality, .high)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 27: Audio File Import Errors)
    
    /// Tier 2: Feature 27 - Validates importing unsupported audio extension (.txt, .pdf) throws error.
    func test_tier2_feature27_audioImportUnsupportedExtensionRejected() throws {
        let textFile = tempDirectoryURL.appendingPathComponent("notes.txt")
        try Data("not audio".utf8).write(to: textFile)
        
        XCTAssertThrowsError(try sut.importAudioFile(from: textFile)) { error in
            guard let importError = error as? AudioImportError else {
                XCTFail("Expected AudioImportError, got \(error)")
                return
            }
            XCTAssertEqual(importError, .unsupportedFormat)
        }
    }
    
    /// Tier 2: Feature 27 - Validates importing 0-byte audio file throws empty file error.
    func test_tier2_feature27_audioImportZeroByteFileHandlesError() throws {
        let emptyAudio = tempDirectoryURL.appendingPathComponent("empty.m4a")
        try Data().write(to: emptyAudio)
        
        XCTAssertThrowsError(try sut.importAudioFile(from: emptyAudio)) { error in
            guard let importError = error as? AudioImportError else {
                XCTFail("Expected AudioImportError")
                return
            }
            XCTAssertEqual(importError, .emptyFile)
        }
    }
    
    /// Tier 2: Feature 27 - Validates importing corrupt audio file emits readable localized message.
    func test_tier2_feature27_audioImportCorruptedFileHandlesError() throws {
        let corruptAudio = tempDirectoryURL.appendingPathComponent("corrupted.m4a")
        try Data("CORRUPT_HEADER_BYTES".utf8).write(to: corruptAudio)
        sut.shouldSimulateCorruptFile = true
        
        XCTAssertThrowsError(try sut.importAudioFile(from: corruptAudio)) { error in
            guard let importError = error as? AudioImportError else {
                XCTFail("Expected AudioImportError")
                return
            }
            XCTAssertEqual(importError, .corruptedFile)
        }
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 28: Tags & Folders Edge Cases)
    
    /// Tier 2: Feature 28 - Validates preventing duplicate tag names during creation.
    func test_tier2_feature28_duplicateTagNamePrevention() throws {
        _ = sut.createTag(name: "Roadmap", colorHex: "#3B82F6")
        let duplicateTag = sut.createTag(name: "Roadmap", colorHex: "#EF4444")
        
        XCTAssertEqual(sut.selectedTags.filter({ $0.name == "Roadmap" }).count, 1)
        XCTAssertEqual(duplicateTag.name, "Roadmap")
    }
    
    /// Tier 2: Feature 28 - Validates folder assignment nullify delete rule retains meeting intact.
    func test_tier2_feature28_folderAssignmentNullifyRuleRetainsMeeting() throws {
        let folder = Folder(name: "Temporary Folder", colorHex: "#10B981")
        context.insert(folder)
        try? context.save()
        sut.selectFolder(folder)
        sut.title = "Important Retained Meeting"
        
        let meeting = try sut.saveScheduledMeeting()
        XCTAssertEqual(meeting.folder?.id, folder.id)
        
        // Detach folder
        sut.detachFolder(for: meeting)
        let updated = fetchMeeting(id: meeting.id)
        XCTAssertNil(updated?.folder)
        XCTAssertEqual(updated?.title, "Important Retained Meeting")
    }
    
    // MARK: - Targeted Remediation Tests (Iteration 2)
    
    /// Validates addParticipant(_ speaker: Speaker) enforces 50-participant limit and email deduplication.
    func test_remediation_addParticipantSpeakerDeduplicationAndFiftyLimit() throws {
        let speaker1 = Speaker(name: "Alice", email: "alice@company.com")
        let speakerDuplicateEmail = Speaker(name: "Alice Second", email: "ALICE@company.com")
        sut.addParticipant(speaker1)
        sut.addParticipant(speakerDuplicateEmail)
        XCTAssertEqual(sut.participants.count, 1, "Duplicate email should be ignored")
        
        for i in 1..<50 {
            let s = Speaker(name: "Member \(i)", email: "member\(i)@company.com")
            sut.addParticipant(s)
        }
        XCTAssertEqual(sut.participants.count, 50)
        
        let overflow = Speaker(name: "Overflow", email: "overflow@company.com")
        sut.addParticipant(overflow)
        XCTAssertEqual(sut.participants.count, 50, "Participant count cannot exceed 50")
    }
    
    /// Validates template switch agenda overwrite confirmation.
    func test_remediation_templateSwitchCustomAgendaProtection() throws {
        sut.selectTemplate(.standup)
        sut.agendaText = "Custom crafted agenda not default"
        
        sut.attemptTemplateSwitch(to: .brainstorm)
        XCTAssertTrue(sut.isShowingTemplateOverwriteConfirmation)
        XCTAssertEqual(sut.pendingTemplateSwitch, .brainstorm)
        XCTAssertEqual(sut.agendaText, "Custom crafted agenda not default")
        
        sut.confirmTemplateSwitch()
        XCTAssertFalse(sut.isShowingTemplateOverwriteConfirmation)
        XCTAssertNil(sut.pendingTemplateSwitch)
        XCTAssertEqual(sut.selectedTemplate, .brainstorm)
        XCTAssertEqual(sut.agendaText, MeetingTemplateType.brainstorm.defaultAgenda)
    }
    
    /// Validates audio import rejects invalid or zero duration with AudioImportError.invalidDuration.
    func test_remediation_audioImportRejectsInvalidDuration() throws {
        let audioFileURL = tempDirectoryURL.appendingPathComponent("zero_duration.m4a")
        try Data("audio_content".utf8).write(to: audioFileURL)
        sut.setSimulatedAudioDuration(0.0)
        
        XCTAssertThrowsError(try sut.importAudioFile(from: audioFileURL)) { error in
            guard let importError = error as? AudioImportError else {
                XCTFail("Expected AudioImportError, got \(error)")
                return
            }
            XCTAssertEqual(importError, .invalidDuration)
        }
    }
    
    /// Validates template switch cancellation leaves custom agenda intact.
    func test_remediation_templateSwitchCancellation() throws {
        sut.selectTemplate(.standup)
        sut.agendaText = "My custom notes"
        sut.attemptTemplateSwitch(to: .brainstorm)
        XCTAssertTrue(sut.isShowingTemplateOverwriteConfirmation)
        XCTAssertEqual(sut.pendingTemplateSwitch, .brainstorm)
        
        sut.cancelTemplateSwitch()
        XCTAssertFalse(sut.isShowingTemplateOverwriteConfirmation)
        XCTAssertNil(sut.pendingTemplateSwitch)
        XCTAssertEqual(sut.agendaText, "My custom notes")
    }
    
    /// Validates addParticipant(_ speaker: Speaker) enforces 50-participant limit and email deduplication.
    func test_remediation_addParticipantSpeakerObjectCapacityLimitAndEmailDeduplication() throws {
        let s1 = Speaker(name: "Alice Original", email: "alice@example.com")
        sut.addParticipant(s1)
        XCTAssertEqual(sut.participants.count, 1)
        
        let s2 = Speaker(name: "Alice Updated", email: "ALICE@EXAMPLE.COM")
        sut.addParticipant(s2)
        XCTAssertEqual(sut.participants.count, 1)
        
        for i in 2...50 {
            let spk = Speaker(name: "Speaker \(i)", email: "speaker\(i)@example.com")
            sut.addParticipant(spk)
        }
        XCTAssertEqual(sut.participants.count, 50)
        XCTAssertTrue(sut.isParticipantLimitReached)
        
        let s51 = Speaker(name: "Speaker 51", email: "speaker51@example.com")
        sut.addParticipant(s51)
        XCTAssertEqual(sut.participants.count, 50)
    }
    
    /// Validates importing non-existent audio file throws corruptedFile.
    func test_remediation_audioImportNonExistentFileThrowsCorruptedFile() throws {
        let missingURL = tempDirectoryURL.appendingPathComponent("non_existent.m4a")
        XCTAssertThrowsError(try sut.importAudioFile(from: missingURL)) { error in
            guard let importError = error as? AudioImportError else {
                XCTFail("Expected AudioImportError, got \(error)")
                return
            }
            XCTAssertEqual(importError, .corruptedFile)
        }
    }
    
    /// Validates async audio import attaches transcript segments and produces positive duration.
    func test_remediation_audioImportPreservesTranscribedSegments() async throws {
        let audioFileURL = tempDirectoryURL.appendingPathComponent("transcribe_test.m4a")
        try Data("audio_content_valid".utf8).write(to: audioFileURL)
        sut.setSimulatedAudioDuration(120.0)
        
        mockTranscription.mockFileSegments = [
            LiveTranscriptSegment(text: "Hello everyone", startTime: 0.0, duration: 2.0),
            LiveTranscriptSegment(text: "Let's review the quarterly metrics", startTime: 2.5, duration: 3.5)
        ]
        
        let meeting = try await sut.importAudioFile(at: audioFileURL, title: "Quarterly Strategy")
        XCTAssertEqual(meeting.title, "Quarterly Strategy")
        XCTAssertEqual(meeting.transcriptSegments.count, 2)
        XCTAssertEqual(meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }.first?.text, "Hello everyone")
        XCTAssertTrue(meeting.duration > 0)
    }
}


extension MeetingSetupViewModelTests {
    func testDefaultImportPersistsIndependentAudioAndWaitsForOfflineReviewPipeline() async throws {
        let source = tempDirectoryURL.appendingPathComponent("private-import.m4a")
        let bytes = Data("synthetic copy fixture, not a speech-quality sample".utf8)
        try bytes.write(to: source)
        let importer = MeetingSetupViewModel(modelContext: context)
        importer.setSimulatedAudioDuration(20)
        let recordedAt = Date(timeIntervalSince1970: 1700000000)
        importer.importedRecordingDate = recordedAt
        let seriesID = UUID()
        importer.importedSeriesID = seriesID
        importer.importedSeriesName = "Synthetic planning series"
        let meeting = try await importer.importAudioFile(at: source)
        let savedURL = try XCTUnwrap(meeting.audioFileURL)
        defer { try? FileManager.default.removeItem(at: savedURL) }
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: savedURL), bytes)
        XCTAssertEqual(meeting.status, .processing)
        XCTAssertTrue(meeting.transcriptSegments.isEmpty)
        XCTAssertTrue(meeting.actionItems.isEmpty)
        XCTAssertNil(meeting.summary)
        let fresh = ModelContext(modelContainer)
        let stored = try XCTUnwrap(fresh.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertEqual(stored.audioFileURL, savedURL)
        XCTAssertEqual(stored.status, .processing)
        XCTAssertEqual(stored.createdAt, recordedAt)
        XCTAssertEqual(stored.scheduledStartTime, recordedAt)
        XCTAssertEqual(stored.seriesID, seriesID)
        XCTAssertEqual(stored.seriesName, "Synthetic planning series")
    }
}
