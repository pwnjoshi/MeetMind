import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingFollowUpLinkTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: MeetingPrepStore!

    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(container)
        suiteName = "MeetingFollowUpLinkTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = MeetingPrepStore(defaults: defaults, key: "prep")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeMeeting(_ title: String, daysAgo: Double, status: MeetingStatus = .completed) -> Meeting {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        let meeting = Meeting(title: title, createdAt: date, scheduledStartTime: date, duration: 1800, status: status)
        context.insert(meeting)
        return meeting
    }

    private func makeViewModel() -> MeetingSetupViewModel {
        let vm = MeetingSetupViewModel(modelContext: context)
        vm.prepStore = store
        return vm
    }

    // MARK: Series

    func testJoiningMeetingWithSeriesReusesItsIdAndName() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let seriesID = UUID()
        earlier.seriesID = seriesID
        earlier.seriesName = "Design reviews"

        let series = MeetingFollowUpLink.series(joining: earlier)
        XCTAssertEqual(series.id, seriesID)
        XCTAssertEqual(series.name, "Design reviews")
        XCTAssertFalse(series.isNew)
    }

    func testJoiningMeetingWithoutSeriesCreatesOneNamedAfterIt() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let series = MeetingFollowUpLink.series(joining: earlier)
        XCTAssertTrue(series.isNew)
        XCTAssertEqual(series.name, "Design review")
        XCTAssertNil(earlier.seriesID, "Choosing a meeting must not change it until the new meeting is saved.")
    }

    func testApplyStampsBothMeetingsWhenEarlierHasNoSeries() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let next = makeMeeting("Design review", daysAgo: -3, status: .scheduled)
        let series = MeetingFollowUpLink.series(joining: earlier)

        MeetingFollowUpLink.apply(seriesID: series.id, seriesName: series.name, previous: earlier, to: next)

        XCTAssertEqual(earlier.seriesID, series.id)
        XCTAssertEqual(next.seriesID, series.id)
        XCTAssertEqual(earlier.seriesName, "Design review")
        XCTAssertEqual(next.seriesName, "Design review")
    }

    func testStampNeverOverwritesAnExistingSeries() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let existing = UUID()
        earlier.seriesID = existing
        earlier.seriesName = "Keep me"

        MeetingFollowUpLink.stamp(earlier, seriesID: UUID(), name: "Other")

        XCTAssertEqual(earlier.seriesID, existing)
        XCTAssertEqual(earlier.seriesName, "Keep me")
    }

    func testApplyWithNilSeriesUnlinks() {
        let meeting = makeMeeting("Weekly", daysAgo: -1, status: .scheduled)
        meeting.seriesID = UUID()
        meeting.seriesName = "Weekly"
        MeetingFollowUpLink.apply(seriesID: nil, seriesName: nil, previous: nil, to: meeting)
        XCTAssertNil(meeting.seriesID)
        XCTAssertNil(meeting.seriesName)
    }

    // MARK: Candidates

    func testCandidatesListSimilarTitlesFirstThenNewest() {
        let unrelatedNewest = makeMeeting("Budget planning", daysAgo: 1)
        let similarOld = makeMeeting("Design review", daysAgo: 30)
        let similarNewer = makeMeeting("Weekly design review", daysAgo: 10)
        let unrelatedOlder = makeMeeting("Hiring sync", daysAgo: 5)
        _ = makeMeeting("Design review upcoming", daysAgo: -2, status: .scheduled)

        let result = MeetingFollowUpLink.candidates(
            forTitle: "Design review",
            in: [unrelatedNewest, similarOld, similarNewer, unrelatedOlder]
        )

        XCTAssertEqual(result.map(\.title), ["Weekly design review", "Design review", "Budget planning", "Hiring sync"])
    }

    func testCandidatesExcludeScheduledAndTheMeetingItself() throws {
        let recorded = makeMeeting("Retro", daysAgo: 3)
        let scheduled = makeMeeting("Retro", daysAgo: -3, status: .scheduled)
        let recording = makeMeeting("Retro", daysAgo: 0, status: .recording)

        let all = [recorded, scheduled, recording]
        XCTAssertEqual(MeetingFollowUpLink.candidates(forTitle: "Retro", in: all).map(\.id), [recorded.id])
        XCTAssertTrue(MeetingFollowUpLink.candidates(forTitle: "Retro", excluding: recorded.id, in: all).isEmpty)
    }

    func testEmptyTitleListsNewestFirst() {
        let older = makeMeeting("A meeting", daysAgo: 9)
        let newer = makeMeeting("Another meeting", daysAgo: 2)
        let result = MeetingFollowUpLink.candidates(forTitle: "  ", in: [older, newer])
        XCTAssertEqual(result.map(\.id), [newer.id, older.id])
    }

    func testTitleSimilarity() {
        XCTAssertTrue(MeetingFollowUpLink.isSimilarTitle("Design-Review!", to: "design review"))
        XCTAssertTrue(MeetingFollowUpLink.isSimilarTitle("Sync with marketing team", to: "Team sync"))
        XCTAssertFalse(MeetingFollowUpLink.isSimilarTitle("Budget planning", to: "Hiring sync"))
        XCTAssertFalse(MeetingFollowUpLink.isSimilarTitle("", to: "Anything"))
    }

    func testPreviousRecordedInSeriesPicksLatestBeforeCutoff() {
        let seriesID = UUID()
        let first = makeMeeting("Standup", daysAgo: 14)
        let second = makeMeeting("Standup", daysAgo: 7)
        let future = makeMeeting("Standup", daysAgo: -7, status: .scheduled)
        for meeting in [first, second, future] { meeting.seriesID = seriesID }

        let found = MeetingFollowUpLink.previousRecorded(inSeries: seriesID, before: Date(), in: [first, second, future])
        XCTAssertEqual(found?.id, second.id)
        XCTAssertNil(MeetingFollowUpLink.previousRecorded(inSeries: UUID(), in: [first, second, future]))
    }

    func testPillTextNamesTheMeetingAndDate() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let text = MeetingFollowUpLink.pillText(for: earlier)
        XCTAssertTrue(text.hasPrefix("Follows up on Design review \u{00B7} "))
        XCTAssertTrue(text.hasSuffix(MeetingFollowUpLink.shortDate(of: earlier)))
    }

    // MARK: View model

    func testSavingFollowUpLinksBothMeetingsInOneSeries() throws {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        try context.save()
        let vm = makeViewModel()
        vm.title = "Design review 2"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        vm.setFollowsUp(earlier)

        let saved = try vm.saveScheduledMeeting()

        XCTAssertNotNil(saved.seriesID)
        XCTAssertEqual(saved.seriesID, earlier.seriesID)
        XCTAssertEqual(saved.seriesName, "Design review")
        XCTAssertEqual(earlier.seriesName, "Design review")
    }

    func testSettingFollowUpToNoneClearsTheSeries() {
        let earlier = makeMeeting("Design review", daysAgo: 7)
        let vm = makeViewModel()
        vm.setFollowsUp(earlier)
        XCTAssertNotNil(vm.scheduledSeriesID)
        vm.setFollowsUp(nil)
        XCTAssertNil(vm.scheduledSeriesID)
        XCTAssertNil(vm.scheduledSeriesName)
        XCTAssertNil(vm.followsUpOn)
    }

    func testFollowUpDraftFromSourceMeetingLinksItOnEditing() {
        let source = makeMeeting("Retro", daysAgo: 2)
        let vm = makeViewModel()
        vm.variant = .followUp
        vm.followUpSource = source
        vm.prepareForEditing()
        XCTAssertTrue(vm.followsUpOn === source)
        XCTAssertNotNil(vm.scheduledSeriesID)
        XCTAssertFalse(vm.hasUnsavedChanges)
    }

    func testChangingFollowUpCountsAsAnEdit() {
        let earlier = makeMeeting("Retro", daysAgo: 2)
        let vm = makeViewModel()
        vm.prepareForEditing()
        XCTAssertFalse(vm.hasUnsavedChanges)
        vm.setFollowsUp(earlier)
        XCTAssertTrue(vm.hasUnsavedChanges)
    }

    func testFollowUpDoesNotInjectOpenActionsIntoAgenda() throws {
        let source = makeMeeting("Retro", daysAgo: 2)
        source.addActionItem(ActionItem(title: "Send estimate", meeting: source))
        let vm = makeViewModel()
        vm.variant = .followUp
        vm.followUpSource = source
        vm.carryOverOpenActions = true
        vm.title = "Retro follow-up"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        vm.prepareForEditing()

        let saved = try vm.saveScheduledMeeting()

        XCTAssertEqual(saved.agendaText ?? "", "")
    }

    // MARK: Important and agenda

    func testNewMeetingHasNoAgendaAndImportantMapsToFavorite() throws {
        let vm = makeViewModel()
        XCTAssertEqual(vm.agendaText, "")
        vm.title = "Board call"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        vm.isImportant = true

        let saved = try vm.saveScheduledMeeting()

        XCTAssertTrue(saved.isFavorite)
        XCTAssertEqual(saved.agendaText ?? "", "")
    }

    func testImportantDefaultsToOff() throws {
        let vm = makeViewModel()
        vm.title = "Casual chat"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        let saved = try vm.saveScheduledMeeting()
        XCTAssertFalse(saved.isFavorite)
    }

    // MARK: Repeat edits

    private func saveRepeatingMeeting(agenda: String = "") throws -> (meeting: Meeting, next: Meeting, start: Date) {
        let vm = makeViewModel()
        vm.title = "Product planning"
        vm.startDate = Date().addingTimeInterval(3600)
        vm.endDate = vm.startDate.addingTimeInterval(1800)
        vm.agendaText = agenda
        vm.recurrence = .weekly
        let start = vm.startDate
        let meeting = try vm.saveScheduledMeeting()
        let all = try context.fetch(FetchDescriptor<Meeting>())
        let next = try XCTUnwrap(all.first { $0.id != meeting.id && $0.title == "Product planning" })
        return (meeting, next, start)
    }

    func testChangingTimeRemovesTheUntouchedGeneratedOccurrence() throws {
        let saved = try saveRepeatingMeeting()
        let removed = MeetingRepeatEditing.removeStaleOccurrence(
            of: saved.meeting,
            oldStart: saved.start,
            oldTitle: "Product planning",
            oldAgenda: nil,
            oldSeriesID: saved.meeting.seriesID,
            oldRecurrence: .weekly,
            newStart: saved.start.addingTimeInterval(86_400),
            newRecurrence: .weekly,
            context: context,
            store: store
        )
        XCTAssertTrue(removed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 1)
    }

    func testUnchangedScheduleKeepsTheGeneratedOccurrence() throws {
        let saved = try saveRepeatingMeeting()
        let removed = MeetingRepeatEditing.removeStaleOccurrence(
            of: saved.meeting,
            oldStart: saved.start,
            oldTitle: "Product planning",
            oldAgenda: nil,
            oldSeriesID: saved.meeting.seriesID,
            oldRecurrence: .weekly,
            newStart: saved.start,
            newRecurrence: .weekly,
            context: context,
            store: store
        )
        XCTAssertFalse(removed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 2)
    }

    func testEditedOccurrenceIsNeverRemoved() throws {
        let saved = try saveRepeatingMeeting()
        saved.next.agendaText = "Roadmap\nHiring"
        let removed = MeetingRepeatEditing.removeStaleOccurrence(
            of: saved.meeting,
            oldStart: saved.start,
            oldTitle: "Product planning",
            oldAgenda: nil,
            oldSeriesID: saved.meeting.seriesID,
            oldRecurrence: .weekly,
            newStart: saved.start.addingTimeInterval(86_400),
            newRecurrence: nil,
            context: context,
            store: store
        )
        XCTAssertFalse(removed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 2)
    }
}
