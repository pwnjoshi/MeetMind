import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ActionItemWriterTests: XCTestCase {
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

    func testCreateLinksMeetingAndParticipantOwner() throws {
        let meeting = Meeting(title: "Finance review")
        let speaker = Speaker(name: "Vaishnavi Shukla")
        context.insert(meeting)
        context.insert(speaker)
        meeting.participants = [speaker]

        let draft = ActionDraft(title: "  Request estimate ", note: "Q4", dueDate: nil, ownerName: "vaishnavi shukla", meetingID: meeting.id)
        let item = try ActionItemWriter.create(from: draft, meetings: [meeting], context: context)

        XCTAssertEqual(item.title, "Request estimate")
        XCTAssertEqual(item.taskDescription, "Q4")
        XCTAssertEqual(item.meeting?.id, meeting.id)
        XCTAssertTrue(meeting.actionItems.contains { $0.id == item.id })
        XCTAssertTrue(item.assignee === speaker)
        XCTAssertEqual(item.assignedByLocalUser, true)
    }

    func testCreateWithoutOwnerOrMeeting() throws {
        let item = try ActionItemWriter.create(from: ActionDraft(title: "Loose"), meetings: [], context: context)
        XCTAssertNil(item.assignee)
        XCTAssertNil(item.meeting)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ActionItem>()), 1)
    }

    func testCreateRejectsEmptyTitle() {
        XCTAssertThrowsError(try ActionItemWriter.create(from: ActionDraft(title: "   "), meetings: [], context: context)) { error in
            XCTAssertEqual(error as? ActionDraftError, .emptyTitle)
        }
    }

    func testNewPersonReusesExistingSpeakerByName() throws {
        let first = try ActionItemWriter.create(from: ActionDraft(title: "One", ownerName: "Riya"), meetings: [], context: context)
        let second = try ActionItemWriter.create(from: ActionDraft(title: "Two", ownerName: "Riya"), meetings: [], context: context)
        XCTAssertTrue(first.assignee === second.assignee)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Speaker>()), 1)
    }

    func testApplyMovesTaskBetweenMeetingsAndClearsOwner() throws {
        let one = Meeting(title: "One")
        let two = Meeting(title: "Two")
        context.insert(one)
        context.insert(two)
        let item = try ActionItemWriter.create(
            from: ActionDraft(title: "Task", ownerName: "Riya", meetingID: one.id),
            meetings: [one, two],
            context: context
        )

        var draft = ActionDraft(item: item)
        draft.meetingID = two.id
        draft.ownerName = nil
        draft.title = "Renamed"
        try ActionItemWriter.apply(draft, to: item, meetings: [one, two], context: context)

        XCTAssertEqual(item.title, "Renamed")
        XCTAssertEqual(item.meeting?.id, two.id)
        XCTAssertNil(item.assignee)
        XCTAssertFalse(one.actionItems.contains { $0.id == item.id })
        XCTAssertTrue(two.actionItems.contains { $0.id == item.id })
    }

    func testViewModelCreateActionAddsToList() throws {
        let vm = ActionItemsViewModel(modelContext: context)
        let meeting = Meeting(title: "Planning")
        context.insert(meeting)
        try context.save()
        let item = try vm.createAction(from: ActionDraft(title: "From sheet", meetingID: meeting.id))
        XCTAssertTrue(vm.allActionItems.contains { $0.id == item.id })
        XCTAssertEqual(item.meeting?.id, meeting.id)
    }

    func testRepeatSchedulesNextWeekInSameSeriesWithParticipants() throws {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 17, minute: 30))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        let meeting = Meeting(title: "Product planning", scheduledStartTime: start)
        let speaker = Speaker(name: "Pawan Joshi")
        context.insert(meeting)
        context.insert(speaker)
        meeting.participants = [speaker]

        let next = try MeetingRepeatService.scheduleNextOccurrence(of: meeting, now: now, context: context)

        let expected = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
        XCTAssertEqual(next.scheduledStartTime, expected)
        XCTAssertNotNil(meeting.seriesID)
        XCTAssertEqual(next.seriesID, meeting.seriesID)
        XCTAssertEqual(next.seriesName, "Product planning")
        XCTAssertEqual(next.status, .scheduled)
        XCTAssertEqual(next.participants.map(\.name), ["Pawan Joshi"])

        let again = try MeetingRepeatService.scheduleNextOccurrence(of: meeting, now: now, context: context)
        XCTAssertEqual(again.id, next.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Meeting>()), 2)
    }

    func testNextOccurrenceSkipsPastWeeks() {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7, hour: 10))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 10))!
        let next = MeetingRepeatService.nextOccurrenceDate(after: base, now: now, calendar: calendar)
        XCTAssertGreaterThan(next, now)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 7 * 86_400 + 3_600)
    }
}
