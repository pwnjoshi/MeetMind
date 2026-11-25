import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Minutes, Actions, Decisions, People and the exports read one record. These tests edit through
/// `MeetingRecordEditor` / `MeetingPeopleEditor` and check what every consumer of the record sees.
@MainActor
final class MeetingRecordSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: MeetingRecordStore!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            Meeting.self, TranscriptSegment.self, Speaker.self, Summary.self,
            ActionItem.self, Note.self, Tag.self, Folder.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        store = MeetingRecordStore(fileURL: nil)
    }

    override func tearDown() async throws {
        store = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: Fixtures

    private struct Fixture {
        let meeting: Meeting
        let summary: Summary
        let asha: Speaker
        let ravi: Speaker
    }

    private func makeFixture(decisions: [String] = ["Ship in October", "Hire a designer"],
                             keyPoints: [String] = ["Launch is Friday"]) throws -> Fixture {
        let meeting = Meeting(title: "Planning", status: .completed)
        context.insert(meeting)
        let asha = Speaker(name: "Asha Rao")
        let ravi = Speaker(name: "Ravi Menon")
        context.insert(asha)
        context.insert(ravi)
        meeting.addParticipant(asha)
        meeting.addParticipant(ravi)
        let summary = Summary(executiveSummary: "Planning went well.", keyPoints: keyPoints,
                              keyDecisions: decisions, meeting: meeting)
        context.insert(summary)
        meeting.summary = summary
        try context.save()
        return Fixture(meeting: meeting, summary: summary, asha: asha, ravi: ravi)
    }

    private func content(_ meeting: Meeting) -> MeetingMinutesContent {
        MeetingMinutesContent.make(from: meeting, record: store.record(for: meeting.id))
    }

    private func plainText(_ meeting: Meeting) -> String {
        let snapshot = DocumentSnapshot.make(from: meeting, record: store.record(for: meeting.id))
        return ExportService().generatePlainText(snapshot: snapshot)
    }

    private func markdown(_ meeting: Meeting) -> String {
        let snapshot = DocumentSnapshot.make(from: meeting, record: store.record(for: meeting.id))
        return ExportService().generateMarkdown(snapshot: snapshot)
    }

    private let suggestionJSON = #"""
    {"sourceSignature":"test","stage":"completed","turns":[{"id":"t1","text":"Rahul will send the estimate tomorrow.","start":12,"end":16,"speaker":"Speaker 1"}],"speakers":[],"analyzedChunks":1,"analysis":[{"discussion":[],"decisions":[],"tasks":[{"title":"Send the estimate","category":"Follow-up","owner":"Rahul","deadlineText":"tomorrow","priority":null,"evidence":[{"turnID":"t1","quote":"Rahul will send the estimate tomorrow."}]}]}]}
    """#

    // MARK: Open issues

    func testOpenIssueDetectionMatchesUnresolvedPhrasesOnly() {
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("The vendor choice is not decided yet."))
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("Budget approval is pending."))
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("Venue remains open."))
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("Date to be confirmed with Finance"))
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("Pricing needs further discussion."))
        XCTAssertTrue(OpenIssueDetector.isOpenIssue("Owner: TBD"))
        XCTAssertFalse(OpenIssueDetector.isOpenIssue("Depending on the venue, we start at nine."))
        XCTAssertFalse(OpenIssueDetector.isOpenIssue("There are no pending items."))
        XCTAssertFalse(OpenIssueDetector.isOpenIssue("The team agreed to ship on Friday."))
    }

    func testPartitionKeepsOrderAndSeparatesOpenIssues() {
        let split = OpenIssueDetector.partition(["Launch is Friday", "Vendor is not decided", "Budget is fine", "QA owner pending"])
        XCTAssertEqual(split.discussion, ["Launch is Friday", "Budget is fine"])
        XCTAssertEqual(split.openIssues, ["Vendor is not decided", "QA owner pending"])
    }

    func testExplicitOpenIssuesAreReadDefensivelyFromAnalysisJSON() {
        let chunked = Data(#"{"analysis":[{"openIssues":[{"text":"Who owns QA?","evidence":[]}]},{"openIssues":["Who owns QA?","Venue"]}]}"#.utf8)
        XCTAssertEqual(OpenIssueDetector.explicitOpenIssues(from: chunked), ["Who owns QA?", "Venue"])
        let topLevel = Data(#"{"openIssues":[]}"#.utf8)
        XCTAssertEqual(OpenIssueDetector.explicitOpenIssues(from: topLevel), [])
        XCTAssertNil(OpenIssueDetector.explicitOpenIssues(from: Data(#"{"analysis":[{"tasks":[]}]}"#.utf8)))
        XCTAssertNil(OpenIssueDetector.explicitOpenIssues(from: Data("not json".utf8)))
        XCTAssertNil(OpenIssueDetector.explicitOpenIssues(from: nil))
    }

    func testContentDerivesOpenIssuesAndOmitsThemFromMinutesExport() throws {
        let fixture = try makeFixture(keyPoints: ["Launch is Friday", "Vendor choice is not decided yet"])
        let record = content(fixture.meeting)
        XCTAssertEqual(record.discussion, ["Launch is Friday"])
        XCTAssertEqual(record.openIssues, ["Vendor choice is not decided yet"])

        let text = plainText(fixture.meeting)
        XCTAssertFalse(text.contains("OPEN ISSUES"))
        XCTAssertFalse(text.contains("Vendor choice is not decided yet"))
        XCTAssertTrue(text.contains("DISCUSSION:\n\u{2022} Launch is Friday"))
        XCTAssertFalse(text.contains("DISCUSSION:\n\u{2022} Launch is Friday\n\u{2022} Vendor"))
    }

    func testExplicitOpenIssuesInAnalysisDataWinOverDerivedOnes() throws {
        let fixture = try makeFixture(keyPoints: ["Launch is Friday", "Vendor choice is not decided yet"])
        fixture.meeting.offlineAnalysisData = Data(#"{"analysis":[{"openIssues":[{"text":"Who owns QA?"}]}]}"#.utf8)
        let record = content(fixture.meeting)
        XCTAssertEqual(record.openIssues, ["Who owns QA?"])
        XCTAssertEqual(record.discussion, ["Launch is Friday", "Vendor choice is not decided yet"])
    }

    func testEmptySectionsAreOmittedFromExports() {
        let meeting = Meeting(title: "Quick Check")
        context.insert(meeting)
        let text = plainText(meeting)
        for heading in ["OPEN ISSUES:", "KEY DECISIONS:", "DISCUSSION:", "EXECUTIVE SUMMARY:", "AGENDA:", "ACTION ITEMS:"] {
            XCTAssertFalse(text.contains(heading), heading)
        }
    }

    // MARK: Decisions

    func testAddDecisionAppendsAndKeepsDecidedByAligned() throws {
        let fixture = try makeFixture()
        try store.update(fixture.meeting.id) {
            $0.setDecider(fixture.asha.id, at: 0)
            $0.setDecider(fixture.ravi.id, at: 1)
        }
        try MeetingRecordEditor.addDecision("Move launch to Friday", decidedBy: fixture.asha.id,
                                            meeting: fixture.meeting, context: context, store: store)
        XCTAssertEqual(fixture.summary.keyDecisions, ["Ship in October", "Hire a designer", "Move launch to Friday"])
        let record = store.record(for: fixture.meeting.id)
        XCTAssertEqual(record.decider(at: 0), fixture.asha.id)
        XCTAssertEqual(record.decider(at: 1), fixture.ravi.id)
        XCTAssertEqual(record.decider(at: 2), fixture.asha.id)
        XCTAssertEqual(content(fixture.meeting).decisions.map(\.decidedBy), ["Asha Rao", "Ravi Menon", "Asha Rao"])
    }

    func testEditingDecisionTextKeepsItsDecidedByAndUpdatesEveryConsumer() throws {
        let fixture = try makeFixture()
        try store.update(fixture.meeting.id) { $0.setDecider(fixture.ravi.id, at: 1) }
        try MeetingRecordEditor.updateDecision(at: 1, text: "Hire two designers", decidedBy: fixture.ravi.id,
                                               meeting: fixture.meeting, context: context, store: store)
        XCTAssertEqual(fixture.summary.keyDecisions[1], "Hire two designers")
        XCTAssertTrue(plainText(fixture.meeting).contains("Hire two designers (Decided by Ravi Menon)"))
        XCTAssertTrue(markdown(fixture.meeting).contains("- Hire two designers (Decided by Ravi Menon)"))
        XCTAssertFalse(plainText(fixture.meeting).contains("Hire a designer"))
    }

    func testDeletingDecisionShiftsDecidedByOfLaterDecisions() throws {
        let fixture = try makeFixture(decisions: ["A", "B", "C"])
        try store.update(fixture.meeting.id) {
            $0.setDecider(fixture.asha.id, at: 0)
            $0.setDecider(fixture.ravi.id, at: 1)
        }
        try MeetingRecordEditor.deleteDecision(at: 0, meeting: fixture.meeting, context: context, store: store)
        XCTAssertEqual(fixture.summary.keyDecisions, ["B", "C"])
        let record = store.record(for: fixture.meeting.id)
        XCTAssertEqual(record.decider(at: 0), fixture.ravi.id)
        XCTAssertNil(record.decider(at: 1))
        XCTAssertEqual(content(fixture.meeting).decisions.map(\.decidedBy), ["Ravi Menon", nil])
    }

    func testApplyDecisionEditsKeepsDeciderWhenTextChangesAndDropsBlankLines() throws {
        let fixture = try makeFixture(decisions: ["A", "B", "C"])
        try store.update(fixture.meeting.id) {
            $0.setDecider(fixture.asha.id, at: 0)
            $0.setDecider(fixture.ravi.id, at: 1)
        }
        let edits = [
            DecisionEdit(originalIndex: 1, text: "B reworded"),
            DecisionEdit(originalIndex: nil, text: "  "),
            DecisionEdit(originalIndex: nil, text: "D new"),
            DecisionEdit(originalIndex: 0, text: "A")
        ]
        try MeetingRecordEditor.applyDecisionEdits(edits, meeting: fixture.meeting, context: context, store: store)
        XCTAssertEqual(fixture.summary.keyDecisions, ["B reworded", "D new", "A"])
        let record = store.record(for: fixture.meeting.id)
        XCTAssertEqual(record.decider(at: 0), fixture.ravi.id)
        XCTAssertNil(record.decider(at: 1))
        XCTAssertEqual(record.decider(at: 2), fixture.asha.id)
    }

    func testDecisionValidationRejectsEmptyAndDuplicateText() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try MeetingRecordEditor.addDecision("  ", decidedBy: nil, meeting: fixture.meeting,
                                                                 context: context, store: store))
        XCTAssertThrowsError(try MeetingRecordEditor.addDecision("ship in october", decidedBy: nil, meeting: fixture.meeting,
                                                                 context: context, store: store))
        XCTAssertEqual(fixture.summary.keyDecisions.count, 2)
    }

    func testDecisionEditIsNotAppliedWhenSidecarCannotBeWritten() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingRecordSync-\(UUID().uuidString)")
        try Data("file".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let failing = MeetingRecordStore(fileURL: blocker.appendingPathComponent("records.json"))
        let fixture = try makeFixture()
        XCTAssertThrowsError(try MeetingRecordEditor.addDecision("New one", decidedBy: fixture.asha.id,
                                                                 meeting: fixture.meeting, context: context, store: failing))
        XCTAssertEqual(fixture.summary.keyDecisions, ["Ship in October", "Hire a designer"])
        XCTAssertNil(failing.record(for: fixture.meeting.id).decider(at: 2))
    }

    // MARK: Actions

    func testActionEditsAppearInDocumentSnapshotAndMinutes() throws {
        let fixture = try makeFixture()
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let item = try MeetingRecordEditor.addAction(title: "Book venue", owner: fixture.asha, dueDate: due,
                                                     priority: .high, meeting: fixture.meeting, context: context)
        XCTAssertEqual(content(fixture.meeting).actions.map(\.title), ["Book venue"])
        XCTAssertEqual(content(fixture.meeting).actions.first?.owner, "Asha Rao")
        XCTAssertTrue(markdown(fixture.meeting).contains("- [ ] **Book venue** - Asha Rao"))

        try MeetingRecordEditor.updateAction(item, title: "Book the venue", owner: fixture.ravi, dueDate: nil,
                                             priority: .low, context: context)
        let edited = markdown(fixture.meeting)
        XCTAssertTrue(edited.contains("**Book the venue** - Ravi Menon"))
        XCTAssertFalse(edited.contains("**Book venue**"))
        XCTAssertTrue(plainText(fixture.meeting).contains("[ ] Book the venue (Ravi Menon)"))

        try MeetingRecordEditor.setCompleted(item, true, context: context)
        XCTAssertTrue(markdown(fixture.meeting).contains("- [x] **Book the venue**"))
        XCTAssertEqual(content(fixture.meeting).actions.first?.statusText, "Done")
        XCTAssertNotNil(item.completedAt)

        try MeetingRecordEditor.deleteAction(item, from: fixture.meeting, context: context)
        XCTAssertTrue(content(fixture.meeting).actions.isEmpty)
        XCTAssertFalse(markdown(fixture.meeting).contains("Book the venue"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActionItem>()).isEmpty)
    }

    func testActionRequiresTitle() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try MeetingRecordEditor.addAction(title: "  ", owner: nil, dueDate: nil, priority: .medium,
                                                               meeting: fixture.meeting, context: context))
        XCTAssertTrue(fixture.meeting.actionItems.isEmpty)
    }

    // MARK: Suggestions

    private func makeSuggestionMeeting() throws -> Meeting {
        let meeting = Meeting(title: "Offline review", status: .completed)
        context.insert(meeting)
        meeting.offlineAnalysisData = Data(suggestionJSON.utf8)
        try context.save()
        return meeting
    }

    func testAcceptingSuggestionMovesItIntoActionsAndExports() throws {
        let meeting = try makeSuggestionMeeting()
        XCTAssertEqual(content(meeting).suggestions.map(\.title), ["Send the estimate"])
        XCTAssertTrue(content(meeting).actions.isEmpty)
        XCTAssertFalse(plainText(meeting).contains("Send the estimate"), "Unreviewed suggestions are not exported")

        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        try MeetingRecordEditor.acceptSuggestion(suggestion, meeting: meeting, context: context)

        let record = content(meeting)
        XCTAssertTrue(record.suggestions.isEmpty)
        XCTAssertEqual(record.actions.map(\.title), ["Send the estimate"])
        XCTAssertEqual(record.actions.first?.owner, "Rahul")
        XCTAssertTrue(plainText(meeting).contains("Send the estimate (Rahul)"))
    }

    func testDiscardingSuggestionRemovesItEverywhereWithoutCreatingActionOrPerson() throws {
        let meeting = try makeSuggestionMeeting()
        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        try MeetingRecordEditor.discardSuggestion(suggestion, meeting: meeting, context: context)
        XCTAssertTrue(content(meeting).suggestions.isEmpty)
        XCTAssertTrue(content(meeting).actions.isEmpty)
        XCTAssertFalse(plainText(meeting).contains("Send the estimate"))
        XCTAssertTrue(try context.fetch(FetchDescriptor<Speaker>()).isEmpty)
    }

    func testAcceptedSuggestionReusesExistingPersonCaseInsensitively() throws {
        let meeting = try makeSuggestionMeeting()
        let rahul = Speaker(name: "rahul")
        context.insert(rahul)
        meeting.addParticipant(rahul)
        try context.save()
        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        try MeetingRecordEditor.acceptSuggestion(suggestion, meeting: meeting, context: context)
        XCTAssertEqual(meeting.actionItems.first?.assignee?.id, rahul.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Speaker>()).count, 1)
    }

    // MARK: Minutes Studio builder

    func testStudioDocumentCarriesSummaryDecidedByOpenIssuesAndDoneActions() throws {
        let snapshot = MinutesMeetingSnapshot(
            meetingID: UUID(),
            title: "Planning",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            agenda: nil,
            participants: [],
            defaultAbsentIDs: [],
            discussion: ["Launch is Friday"],
            decisions: ["Ship in October"],
            actionItems: [MinutesActionLine(title: "Book venue", owner: "Asha Rao", due: nil, isCompleted: true)],
            isFinalized: false,
            summary: "Planning went well.",
            openIssues: ["Vendor not decided"],
            decisionDeciders: ["Ravi Menon"]
        )
        let document = MinutesDocumentBuilder.build(snapshot: snapshot, config: .standard(), templateName: "T", documentHeading: "H")
        XCTAssertEqual(document.blocks.first?.id, "summary")
        let ids = document.blocks.map(\.id)
        let discussionIndex = try XCTUnwrap(ids.firstIndex(of: "discussion"))
        XCTAssertEqual(ids[discussionIndex + 1], "openIssues")
        let decisions = try XCTUnwrap(document.blocks.first { $0.id == "decisions" })
        XCTAssertEqual(decisions.lines, ["1. Ship in October (Decided by Ravi Menon)"])
        let actions = try XCTUnwrap(document.blocks.first { $0.id == "actionItems" })
        XCTAssertEqual(actions.lines, ["Book venue \u{00B7} Asha Rao \u{00B7} Done"])
    }

    // MARK: People

    func testAddingNonSpeakingAttendeePersistsAndAppearsInAttendanceAndOwnerPickers() throws {
        let fixture = try makeFixture()
        let added = try MeetingPeopleEditor.addNewAttendee(name: "  Meera Kapoor ", email: "meera@studio.example", role: "Designer",
                                                           meeting: fixture.meeting, context: context)
        XCTAssertEqual(added.name, "Meera Kapoor")
        XCTAssertEqual(added.email, "meera@studio.example")
        XCTAssertEqual(added.role, "Designer")
        XCTAssertFalse(MeetingPeopleEditor.isAbsent(added, in: fixture.meeting))
        XCTAssertTrue(content(fixture.meeting).present.contains(where: { $0.name == "Meera Kapoor" }))
        XCTAssertTrue(MeetingPeopleEditor.ownerChoices(for: fixture.meeting).contains(where: { $0.id == added.id }))
        XCTAssertTrue(plainText(fixture.meeting).contains("Meera Kapoor (Designer)"))

        let fresh = ModelContext(container)
        let saved = try XCTUnwrap(fresh.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertTrue(saved.namedAttendees.contains(where: { $0.name == "Meera Kapoor" }))
        XCTAssertTrue(saved.transcriptSegments.isEmpty)

        let action = try MeetingRecordEditor.addAction(title: "Mock the landing page", owner: added, dueDate: nil,
                                                       priority: .medium, meeting: fixture.meeting, context: context)
        XCTAssertEqual(action.assignee?.id, added.id)
        try MeetingRecordEditor.addDecision("Use the new brand colours", decidedBy: added.id,
                                            meeting: fixture.meeting, context: context, store: store)
        XCTAssertEqual(content(fixture.meeting).decisions.last?.decidedBy, "Meera Kapoor")
    }

    func testAttendeeCanBeMarkedAbsentAndBackAndAppearsUnderAbsent() throws {
        let fixture = try makeFixture()
        let added = try MeetingPeopleEditor.addNewAttendee(name: "Meera Kapoor", email: nil, role: nil,
                                                           meeting: fixture.meeting, context: context)
        try MeetingPeopleEditor.setAbsent(true, person: added, meeting: fixture.meeting, context: context)
        XCTAssertEqual(content(fixture.meeting).absent.map(\.name), ["Meera Kapoor"])
        XCTAssertTrue(markdown(fixture.meeting).contains("## Absent\n- Meera Kapoor"))
        try MeetingPeopleEditor.setAbsent(false, person: added, meeting: fixture.meeting, context: context)
        XCTAssertTrue(content(fixture.meeting).absent.isEmpty)
    }

    func testAddingSameNameTwiceDoesNotDuplicateAttendee() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(try MeetingPeopleEditor.addNewAttendee(name: "asha rao", email: nil, role: nil,
                                                                    meeting: fixture.meeting, context: context)) { error in
            XCTAssertEqual(error as? MeetingPeopleError, .duplicate("Asha Rao"))
        }
        let other = Speaker(name: "ASHA RAO")
        context.insert(other)
        XCTAssertThrowsError(try MeetingPeopleEditor.addAttendee(other, to: fixture.meeting, context: context))
        XCTAssertEqual(fixture.meeting.namedAttendees.count, 2)
        XCTAssertThrowsError(try MeetingPeopleEditor.addNewAttendee(name: "   ", email: nil, role: nil,
                                                                    meeting: fixture.meeting, context: context))
    }

    func testPickerOffersKnownPeopleFromOtherMeetingsOncePerName() throws {
        let fixture = try makeFixture()
        let earlier = Meeting(title: "Earlier")
        context.insert(earlier)
        let dev = Speaker(name: "Dev Patel", email: "dev@studio.example")
        let devDuplicate = Speaker(name: "dev patel")
        let voice = Speaker(name: "Speaker 3")
        voice.recordingVoiceLabel = "Speaker 3"
        for speaker in [dev, devDuplicate, voice] { context.insert(speaker) }
        earlier.addParticipant(dev)
        earlier.addParticipant(devDuplicate)
        earlier.addParticipant(voice)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Speaker>())
        let offered = MeetingPeopleEditor.candidates(from: all, for: fixture.meeting)
        XCTAssertEqual(offered.map(\.name), ["Dev Patel"])
        XCTAssertEqual(offered.first?.id, dev.id)
        XCTAssertEqual(MeetingPeopleEditor.candidates(from: all, for: fixture.meeting, query: "dev@").count, 1)
        XCTAssertTrue(MeetingPeopleEditor.candidates(from: all, for: fixture.meeting, query: "zzz").isEmpty)

        try MeetingPeopleEditor.addAttendee(dev, to: fixture.meeting, context: context)
        XCTAssertTrue(MeetingPeopleEditor.candidates(from: all, for: fixture.meeting).isEmpty)
        XCTAssertTrue(fixture.meeting.namedAttendees.contains(where: { $0.id == dev.id }))
    }

    func testNewAttendeeReusesExistingLocalPersonInsteadOfCreatingDuplicate() throws {
        let fixture = try makeFixture()
        let known = Speaker(name: "Dev Patel", email: "dev@studio.example")
        context.insert(known)
        try context.save()
        let added = try MeetingPeopleEditor.addNewAttendee(name: "dev patel", email: nil, role: "Engineer",
                                                           meeting: fixture.meeting, context: context)
        XCTAssertEqual(added.id, known.id)
        XCTAssertEqual(added.role, "Engineer")
        let matching = try context.fetch(FetchDescriptor<Speaker>()).filter { $0.name.lowercased() == "dev patel" }
        XCTAssertEqual(matching.count, 1)
    }

    func testRemovingAttendeeKeepsGlobalSpeakerAndTheirActions() throws {
        let fixture = try makeFixture()
        let added = try MeetingPeopleEditor.addNewAttendee(name: "Meera Kapoor", email: nil, role: nil,
                                                           meeting: fixture.meeting, context: context)
        let action = try MeetingRecordEditor.addAction(title: "Mock the page", owner: added, dueDate: nil,
                                                       priority: .medium, meeting: fixture.meeting, context: context)
        try MeetingPeopleEditor.setAbsent(true, person: added, meeting: fixture.meeting, context: context)

        try MeetingPeopleEditor.removeAttendee(added, from: fixture.meeting, context: context)

        XCTAssertFalse(fixture.meeting.participants.contains(where: { $0.id == added.id }))
        XCTAssertFalse((fixture.meeting.absentParticipantIDs ?? []).contains(added.id))
        let speakers = try context.fetch(FetchDescriptor<Speaker>())
        XCTAssertTrue(speakers.contains(where: { $0.id == added.id }))
        XCTAssertEqual(action.assignee?.id, added.id)
        XCTAssertTrue(MeetingPeopleEditor.candidates(from: speakers, for: fixture.meeting).contains(where: { $0.id == added.id }))
    }

    func testPersonWhoSpokeCannotBeRemovedFromMeeting() throws {
        let fixture = try makeFixture()
        let segment = TranscriptSegment(text: "Let's start.", startTime: 0, endTime: 3, speaker: fixture.asha)
        context.insert(segment)
        fixture.meeting.addTranscriptSegment(segment)
        try context.save()
        XCTAssertFalse(MeetingPeopleEditor.canRemove(fixture.asha, from: fixture.meeting))
        XCTAssertThrowsError(try MeetingPeopleEditor.removeAttendee(fixture.asha, from: fixture.meeting, context: context))
        XCTAssertTrue(fixture.meeting.participants.contains(where: { $0.id == fixture.asha.id }))
        XCTAssertTrue(MeetingPeopleEditor.canRemove(fixture.ravi, from: fixture.meeting))
    }

    func testRenamingAttendeeUpdatesRecordAndRejectsDuplicates() throws {
        let fixture = try makeFixture()
        try MeetingPeopleEditor.updatePerson(fixture.ravi, name: "Ravi M. Menon", email: " ravi@studio.example ", role: "",
                                             meeting: fixture.meeting, context: context)
        XCTAssertEqual(fixture.ravi.name, "Ravi M. Menon")
        XCTAssertEqual(fixture.ravi.email, "ravi@studio.example")
        XCTAssertNil(fixture.ravi.role)
        XCTAssertThrowsError(try MeetingPeopleEditor.updatePerson(fixture.ravi, name: "asha rao", email: nil, role: nil,
                                                                  meeting: fixture.meeting, context: context))
        XCTAssertEqual(fixture.ravi.name, "Ravi M. Menon")
        XCTAssertTrue(plainText(fixture.meeting).contains("Ravi M. Menon"))
    }
}
