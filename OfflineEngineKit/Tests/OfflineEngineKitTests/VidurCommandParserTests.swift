import XCTest
@testable import OfflineEngineKit

/// Wednesday 12 March 2025, 09:00 UTC.
enum VidurTestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static var now: Date { date(2025, 3, 12, 9, 0) }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

final class VidurCommandParserTests: XCTestCase {
    private func parse(_ text: String) -> VidurCommandOutcome {
        VidurCommandParser.parse(text, now: VidurTestClock.now, calendar: VidurTestClock.calendar)
    }

    private func schedule(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> VidurScheduleDraft? {
        guard case .command(.scheduleMeeting(let draft)) = parse(text) else {
            XCTFail("Expected a schedule command for \(text)", file: file, line: line)
            return nil
        }
        return draft
    }

    func testSchedulesWithTitleDatePeople() {
        guard let draft = schedule("schedule a design review tomorrow at 4 with Maya and Arjun") else { return }
        XCTAssertEqual(draft.title, "Design review")
        XCTAssertEqual(draft.start, VidurTestClock.date(2025, 3, 13, 16, 0))
        XCTAssertEqual(draft.durationMinutes, 30)
        XCTAssertEqual(draft.people, ["Maya", "Arjun"])
        XCTAssertNil(draft.repeatRule)
        XCTAssertFalse(draft.timeAssumed)
    }

    func testRepeatDurationAndWeekday() {
        guard let draft = schedule("schedule team sync every monday at 10am for 45 minutes with Neha") else { return }
        XCTAssertEqual(draft.title, "Team sync")
        XCTAssertEqual(draft.start, VidurTestClock.date(2025, 3, 17, 10, 0))
        XCTAssertEqual(draft.durationMinutes, 45)
        XCTAssertEqual(draft.repeatRule, .weekly)
        XCTAssertEqual(draft.people, ["Neha"])
    }

    func testMissingTimeIsAssumedAndFlagged() {
        guard let draft = schedule("schedule a meeting tomorrow") else { return }
        XCTAssertEqual(draft.title, "Meeting")
        XCTAssertEqual(draft.start, VidurTestClock.date(2025, 3, 13, 10, 0))
        XCTAssertTrue(draft.timeAssumed)
    }

    func testHinglishSchedule() {
        guard let draft = schedule("kal shaam 5 baje design review rakho") else { return }
        XCTAssertEqual(draft.title, "Design review")
        XCTAssertEqual(draft.start, VidurTestClock.date(2025, 3, 13, 17, 0))
    }

    func testWakePhraseAndFillerAreIgnored() {
        guard let draft = schedule("hey vidur schedule a call with Maya tomorrow at 3pm") else { return }
        XCTAssertEqual(draft.title, "Meeting")
        XCTAssertEqual(draft.people, ["Maya"])
        XCTAssertEqual(draft.start, VidurTestClock.date(2025, 3, 13, 15, 0))
    }

    func testRemindSomeoneWithDeadline() {
        guard case .command(.addAction(let draft)) = parse("remind Pawan to send the deck by Friday") else {
            return XCTFail("Expected an action")
        }
        XCTAssertEqual(draft.title, "Send the deck")
        XCTAssertEqual(draft.assignee, "Pawan")
        XCTAssertEqual(draft.due, VidurTestClock.date(2025, 3, 14, 18, 0))
    }

    func testRemindMeWithTime() {
        guard case .command(.addAction(let draft)) = parse("remind me to call John tomorrow at 5pm") else {
            return XCTFail("Expected an action")
        }
        XCTAssertEqual(draft.title, "Call John")
        XCTAssertNil(draft.assignee)
        XCTAssertEqual(draft.due, VidurTestClock.date(2025, 3, 13, 17, 0))
    }

    func testAddTaskPhrase() {
        guard case .command(.addAction(let draft)) = parse("add a task to review the budget") else {
            return XCTFail("Expected an action")
        }
        XCTAssertEqual(draft.title, "Review the budget")
        XCTAssertNil(draft.due)
    }

    func testCompleteAction() {
        XCTAssertEqual(parse("mark send the deck as done"), .command(.completeAction(query: "send deck")))
    }

    func testOpenAndImportantAndRecording() {
        XCTAssertEqual(parse("open last design review"),
                       .command(.openMeeting(query: "design review", preferLast: true)))
        XCTAssertEqual(parse("start recording"), .command(.startRecording))
        XCTAssertEqual(parse("mark the design review as important"),
                       .command(.setImportant(query: "design review", preferLast: false, important: true)))
        XCTAssertEqual(parse("open my tasks"), .command(.openScreen(.actions)))
    }

    func testUnsupportedRequestIsNeverFakedAsSuccess() {
        guard case .reply(let text) = parse("delete all meetings") else { return XCTFail("Expected a reply") }
        XCTAssertTrue(text.contains("delete"))
        XCTAssertTrue(text.contains("schedule meetings"))
    }

    func testQuestionsAreNotCommands() {
        for question in ["what did we decide about pricing?", "who owns the deck", "Which tasks are still open",
                         "Summarize the last meeting", "what is overdue for me?"] {
            XCTAssertEqual(parse(question), .none, question)
        }
    }

    func testTitleMatcher() {
        let now = VidurTestClock.now
        let old = VidurNamedItem(id: UUID(), title: "Design review", date: now.addingTimeInterval(-7 * 86_400))
        let future = VidurNamedItem(id: UUID(), title: "Design review", date: now.addingTimeInterval(86_400))
        let budget = VidurNamedItem(id: UUID(), title: "Budget sync", date: now.addingTimeInterval(-2 * 86_400))
        let items = [old, future, budget]
        XCTAssertEqual(VidurTitleMatcher.best(query: "design review", in: items, preferLast: true, now: now)?.id, old.id)
        XCTAssertEqual(VidurTitleMatcher.best(query: "design review", in: items, now: now)?.id, future.id)
        XCTAssertEqual(VidurTitleMatcher.best(query: "", in: items, preferLast: true, now: now)?.id, budget.id)
        XCTAssertEqual(VidurTitleMatcher.best(query: "budget", in: items, now: now)?.id, budget.id)
        XCTAssertNil(VidurTitleMatcher.best(query: "zebra", in: items, now: now))
    }

    func testWakeWord() {
        XCTAssertEqual(VidurWakeWord.detect(in: "hey vidur what did we decide")?.remainder, "what did we decide")
        XCTAssertEqual(VidurWakeWord.detect(in: "Hey, Vidur!")?.remainder, "")
        XCTAssertEqual(VidurWakeWord.detect(in: "ok vidhur schedule a meeting")?.remainder, "schedule a meeting")
        XCTAssertNil(VidurWakeWord.detect(in: "hey video"))
        XCTAssertNil(VidurWakeWord.detect(in: "hello there"))
        XCTAssertEqual(VidurWakeWord.stripLeading("Hey Vidur, what is overdue"), "what is overdue")
    }
}
