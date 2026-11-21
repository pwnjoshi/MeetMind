import XCTest
import SwiftData
@testable import MeetMind

@MainActor
final class NotesOnlyMinutesBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func test_emptyDraftIsRejected() {
        let draft = NotesOnlyDraft(discussion: "  \n ", decisions: ["   "], actions: [NotesOnlyActionDraft(title: " ")])
        XCTAssertFalse(draft.hasContent)
        XCTAssertThrowsError(try NotesOnlyMinutesBuilder.save(draft: draft, context: context)) { error in
            XCTAssertEqual(error as? NotesOnlyMinutesError, .emptyNotes)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 0)
    }

    func test_savesMeetingWithoutAudioAsDraftMinutes() throws {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = NotesOnlyDraft(
            discussion: "Launch target is 24 November. Budget waits on a Finance estimate.",
            decisions: ["Get a Finance estimate before approval", "  "],
            actions: [NotesOnlyActionDraft(title: "Request the estimate", owner: "Vaishnavi Shukla", dueDate: due)]
        )
        let meeting = try NotesOnlyMinutesBuilder.save(draft: draft, title: "Product planning", context: context)

        XCTAssertEqual(meeting.title, "Product planning")
        XCTAssertEqual(meeting.status, .completed)
        XCTAssertNil(meeting.audioFileURL)
        XCTAssertFalse(meeting.hasAudio)
        XCTAssertEqual(meeting.minutesNeedFinalization, true)

        let summary = try XCTUnwrap(meeting.summary)
        XCTAssertEqual(summary.keyPoints, ["Launch target is 24 November.", "Budget waits on a Finance estimate."])
        XCTAssertEqual(summary.keyDecisions, ["Get a Finance estimate before approval"])
        XCTAssertEqual(summary.modelVersion, NotesOnlyMinutesBuilder.modelVersion)

        XCTAssertEqual(meeting.notes.count, 2)
        XCTAssertTrue(meeting.notes.allSatisfy { $0.timestamp == 0 && !$0.isBookmark })
        XCTAssertTrue(meeting.notes.contains { $0.content == "Decision: Get a Finance estimate before approval" })

        XCTAssertEqual(meeting.actionItems.count, 1)
        let action = try XCTUnwrap(meeting.actionItems.first)
        XCTAssertEqual(action.title, "Request the estimate")
        XCTAssertEqual(action.assignee?.name, "Vaishnavi Shukla")
        XCTAssertEqual(action.dueDate, due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 1)
    }

    func test_sameNotesProduceSameSummary() throws {
        let draft = NotesOnlyDraft(discussion: "- First point\n\u{2022} Second point")
        let first = try NotesOnlyMinutesBuilder.save(draft: draft, context: context)
        let second = try NotesOnlyMinutesBuilder.save(draft: draft, context: context)
        XCTAssertEqual(first.summary?.keyPoints, ["First point", "Second point"])
        XCTAssertEqual(first.summary?.keyPoints, second.summary?.keyPoints)
        XCTAssertEqual(first.summary?.executiveSummary, second.summary?.executiveSummary)
        XCTAssertEqual(first.title, NotesOnlyMinutesBuilder.defaultTitle)
    }

    func test_existingMeetingIsCompletedInPlace() throws {
        let existing = Meeting(title: "Weekly sync", duration: 0, status: .recording)
        context.insert(existing)
        try context.save()

        let draft = NotesOnlyDraft(decisions: ["Ship on Friday"])
        let saved = try NotesOnlyMinutesBuilder.save(draft: draft, title: "Ignored", existingMeeting: existing, context: context)

        XCTAssertTrue(saved === existing)
        XCTAssertEqual(existing.title, "Weekly sync")
        XCTAssertEqual(existing.status, .completed)
        XCTAssertEqual(existing.minutesNeedFinalization, true)
        XCTAssertEqual(existing.summary?.executiveSummary, "Ship on Friday")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 1)
    }

    func test_actionOwnerIsReusedAcrossActions() throws {
        let draft = NotesOnlyDraft(actions: [
            NotesOnlyActionDraft(title: "Draft agenda", owner: "Asha"),
            NotesOnlyActionDraft(title: "Book room", owner: " Asha "),
            NotesOnlyActionDraft(title: "Send notes")
        ])
        let meeting = try NotesOnlyMinutesBuilder.save(draft: draft, context: context)
        XCTAssertEqual(meeting.actionItems.count, 3)
        XCTAssertEqual(meeting.participants.filter { $0.name == "Asha" }.count, 1)
        XCTAssertEqual(meeting.actionItems.filter { $0.assignee == nil }.count, 1)
    }

    func test_attachedPhotoUsesCaptionAsNoteText() throws {
        let meeting = Meeting(title: "Live", duration: 0, status: .recording)
        context.insert(meeting)
        let viewModel = LiveRecordingViewModel(meeting: meeting, modelContext: context)
        viewModel.attachPhoto(url: URL(fileURLWithPath: "/tmp/caption-test.jpg"), caption: "  Launch target ")
        viewModel.attachPhoto(url: URL(fileURLWithPath: "/tmp/no-caption-test.jpg"))

        let contents = meeting.notes.map(\.content).sorted()
        XCTAssertEqual(contents, ["Launch target", "Whiteboard photo: no-caption-test.jpg"])
        XCTAssertTrue(meeting.notes.allSatisfy { $0.hasImage })
    }

    func test_composeBarPlaceholderUsesTimecode() {
        XCTAssertEqual(LiveNoteComposeBar.placeholder(for: 948), "Note at 15:48")
        XCTAssertEqual(LiveNoteComposeBar.placeholder(for: 3_725), "Note at 1:02:05")
        XCTAssertEqual(LiveNoteComposeBar.placeholder(for: .nan), "Note at 00:00")
    }
}
