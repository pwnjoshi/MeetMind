import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ActionListLogicTests: XCTestCase {
    private let me = "Dr. Sachin Ghai"
    private var calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now)!
    }

    func testSectionsSplitYoursFromWaitingOnOthers() {
        let mine = ActionItem(title: "Mine", assigneeName: me)
        let unassigned = ActionItem(title: "Nobody", assigneeName: nil)
        let theirs = ActionItem(title: "Theirs", assigneeName: "Vaishnavi Shukla")
        let sections = ActionListLogic.sections([mine, unassigned, theirs], localName: me)
        XCTAssertEqual(sections.yours.map(\.title), ["Mine", "Nobody"])
        XCTAssertEqual(sections.waitingOnOthers.map(\.title), ["Theirs"])
    }

    func testOwnerNameMatchIgnoresCaseAndWhitespace() {
        let item = ActionItem(title: "Case", assigneeName: "  dr. sachin ghai ")
        XCTAssertTrue(ActionListLogic.isAssignedToLocalUser(item, localName: me))
        XCTAssertFalse(ActionListLogic.isWaitingOnOthers(item, localName: me))
    }

    func testScopes() {
        let mine = ActionItem(title: "Mine", assigneeName: me)
        let theirs = ActionItem(title: "Theirs", assigneeName: "Pawan Joshi")
        theirs.assignedByLocalUser = true
        let items = [mine, theirs]
        XCTAssertEqual(ActionListLogic.apply(scope: .all, to: items, localName: me).count, 2)
        XCTAssertEqual(ActionListLogic.apply(scope: .assignedToMe, to: items, localName: me).map(\.title), ["Mine"])
        XCTAssertEqual(ActionListLogic.apply(scope: .assignedByMe, to: items, localName: me).map(\.title), ["Theirs"])
    }

    func testSortByDueDatePutsEarliestFirstUndatedLastAndDoneAfterOpen() {
        let late = ActionItem(title: "Late", assigneeName: nil, dueDate: day(5))
        let soon = ActionItem(title: "Soon", assigneeName: nil, dueDate: day(1))
        let undated = ActionItem(title: "Undated", assigneeName: nil)
        let done = ActionItem(title: "Done", assigneeName: nil, dueDate: day(-3))
        done.isCompleted = true
        let sorted = ActionListLogic.sorted([undated, done, late, soon], by: .dueDate)
        XCTAssertEqual(sorted.map(\.title), ["Soon", "Late", "Undated", "Done"])
    }

    func testSortByMeetingGroupsByTitleThenDueDate() {
        let alpha = Meeting(title: "Alpha")
        let beta = Meeting(title: "Beta")
        let a2 = ActionItem(title: "A2", assigneeName: nil, dueDate: day(4))
        let a1 = ActionItem(title: "A1", assigneeName: nil, dueDate: day(2))
        let b1 = ActionItem(title: "B1", assigneeName: nil, dueDate: day(1))
        let loose = ActionItem(title: "Loose", assigneeName: nil, dueDate: day(0))
        alpha.addActionItem(a2)
        alpha.addActionItem(a1)
        beta.addActionItem(b1)
        let sorted = ActionListLogic.sorted([loose, b1, a2, a1], by: .meeting)
        XCTAssertEqual(sorted.map(\.title), ["A1", "A2", "B1", "Loose"])
    }

    func testDueInfoLabels() {
        let overdue = ActionItem(title: "o", assigneeName: nil, dueDate: day(-2))
        let today = ActionItem(title: "t", assigneeName: nil, dueDate: now)
        let later = ActionItem(title: "l", assigneeName: nil, dueDate: day(10))
        let doneLate = ActionItem(title: "d", assigneeName: nil, dueDate: day(-2))
        doneLate.isCompleted = true
        XCTAssertEqual(ActionListLogic.dueInfo(for: overdue, now: now, calendar: calendar),
                       ActionDueInfo(text: "Overdue", isOverdue: true))
        XCTAssertEqual(ActionListLogic.dueInfo(for: today, now: now, calendar: calendar),
                       ActionDueInfo(text: "Today", isOverdue: false))
        XCTAssertEqual(ActionListLogic.dueInfo(for: later, now: now, calendar: calendar)?.isOverdue, false)
        XCTAssertNotEqual(ActionListLogic.dueInfo(for: later, now: now, calendar: calendar)?.text, "Today")
        XCTAssertEqual(ActionListLogic.dueInfo(for: doneLate, now: now, calendar: calendar)?.isOverdue, false)
        XCTAssertNil(ActionListLogic.dueInfo(for: ActionItem(title: "n", assigneeName: nil), now: now, calendar: calendar))
    }

    func testOwnerOptionsDeduplicateAndIncludeParticipants() {
        let meeting = Meeting(title: "Finance review")
        meeting.participants = [Speaker(name: "Vaishnavi Shukla"), Speaker(name: "pawan joshi")]
        let options = ActionListLogic.ownerOptions(
            localName: me,
            meeting: meeting,
            extras: ["Pawan Joshi", "Riya"],
            current: "vaishnavi shukla"
        )
        XCTAssertEqual(options, [me, "Vaishnavi Shukla", "pawan joshi", "Riya"])
    }

    func testViewModelAppliesScopeSortAndFilter() throws {
        let vm = ActionItemsViewModel()
        vm.localUserName = me
        let mine = ActionItem(title: "Mine", assigneeName: me, dueDate: day(3))
        let theirs = ActionItem(title: "Theirs", assigneeName: "Pawan Joshi", dueDate: day(1))
        let done = ActionItem(title: "Done", assigneeName: me, dueDate: day(2))
        done.isCompleted = true
        vm.allActionItems = [mine, theirs, done]

        XCTAssertEqual(vm.visibleActionItems.map(\.title), ["Theirs", "Mine", "Done"])
        XCTAssertEqual(vm.actionSections.yours.map(\.title), ["Mine", "Done"])
        XCTAssertEqual(vm.actionSections.waitingOnOthers.map(\.title), ["Theirs"])

        vm.selectedFilterScope = .pending
        XCTAssertEqual(vm.visibleActionItems.map(\.title), ["Theirs", "Mine"])

        vm.selectedOwnerScope = .assignedToMe
        XCTAssertEqual(vm.visibleActionItems.map(\.title), ["Mine"])
        XCTAssertTrue(vm.isWaitingOnOthers(theirs))
        XCTAssertFalse(vm.isWaitingOnOthers(mine))
    }
}
