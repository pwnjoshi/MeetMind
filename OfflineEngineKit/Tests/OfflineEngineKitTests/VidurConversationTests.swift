import XCTest
@testable import OfflineEngineKit

final class VidurConversationTests: XCTestCase {
    private var busyDay: VidurAssistantContext {
        VidurAssistantContext(
            userName: "Arjun Mehta",
            upcomingToday: [
                VidurMeetingBrief(title: "Design review", start: VidurTestClock.date(2025, 3, 12, 16, 0)),
                VidurMeetingBrief(title: "Finance sync", start: VidurTestClock.date(2025, 3, 12, 17, 30))
            ],
            nextMeeting: VidurMeetingBrief(title: "Design review", start: VidurTestClock.date(2025, 3, 12, 16, 0)),
            nextMeetingHasHistory: true,
            overdueActionCount: 2,
            openActionCount: 5,
            unreviewedSuggestionCount: 3,
            lastMeetingTitle: "Launch planning",
            lastMeetingHasMinutes: true,
            isRecording: false,
            hasAnyMeetings: true)
    }

    private func reply(_ text: String, context: VidurAssistantContext? = nil, seed: Int = 0) -> VidurSmallTalkReply? {
        VidurSmallTalk.reply(to: text, context: context ?? busyDay, seed: seed,
                             now: VidurTestClock.now, calendar: VidurTestClock.calendar)
    }

    func testGreetingUsesRealData() throws {
        let greeting = try XCTUnwrap(reply("hi"))
        XCTAssertEqual(greeting.intent, .greeting)
        XCTAssertTrue(greeting.text.contains("Arjun"), greeting.text)
        XCTAssertTrue(greeting.text.contains("2 meetings left today"), greeting.text)
        XCTAssertTrue(greeting.text.contains("Design review at 4:00 PM"), greeting.text)
        XCTAssertTrue(greeting.text.contains("2 overdue actions"), greeting.text)
        XCTAssertTrue(greeting.text.contains("quick recap of the last Design review"), greeting.text)
        XCTAssertTrue((2...3).contains(greeting.suggestions.count), "\(greeting.suggestions)")
        XCTAssertTrue(greeting.suggestions.contains("What is overdue for me?"), "\(greeting.suggestions)")
    }

    func testGreetingVariesWithSeed() throws {
        let first = try XCTUnwrap(reply("hello", seed: 0))
        let second = try XCTUnwrap(reply("hello", seed: 1))
        XCTAssertNotEqual(first.text, second.text)
        XCTAssertEqual(first.text, try XCTUnwrap(reply("hello", seed: 0)).text)
    }

    func testEmptyAndRecordingGreetings() throws {
        let empty = try XCTUnwrap(reply("hey vidur", context: VidurAssistantContext()))
        XCTAssertEqual(empty.intent, .greeting)
        XCTAssertTrue(empty.text.contains("schedule"), empty.text)
        XCTAssertFalse(empty.suggestions.isEmpty)
        let recording = try XCTUnwrap(reply("hi", context: VidurAssistantContext(isRecording: true)))
        XCTAssertTrue(recording.text.contains("record"), recording.text)
    }

    func testOtherSmallTalkIntents() {
        XCTAssertEqual(reply("thanks!")?.intent, .thanks)
        XCTAssertEqual(reply("thank you vidur")?.intent, .thanks)
        XCTAssertEqual(reply("who are you")?.intent, .whoAreYou)
        XCTAssertEqual(reply("what can you do?")?.intent, .capabilities)
        XCTAssertEqual(reply("how are you")?.intent, .howAreYou)
        XCTAssertEqual(reply("bye")?.intent, .goodbye)
        XCTAssertEqual(reply("ok")?.intent, .acknowledge)
        XCTAssertEqual(reply("kaise ho")?.intent, .howAreYou)
        XCTAssertEqual(reply("namaste")?.intent, .greeting)
        XCTAssertEqual(reply("good morning")?.intent, .greeting)
        XCTAssertTrue(reply("who are you")?.text.contains("Vidur") ?? false)
        XCTAssertTrue(reply("what can you do")?.text.contains("schedule") ?? false)
    }

    func testRealQuestionsAreNotSmallTalk() {
        for text in ["what did we decide?", "which tasks are open", "hi can you list the decisions from the budget meeting",
                     "schedule a meeting tomorrow", "thanks for the budget summary, now list the tasks from yesterday please"] {
            XCTAssertNil(reply(text), text)
        }
    }

    func testRouterSeparatesSmallTalkCommandsAndQuestions() {
        func route(_ text: String) -> VidurConversationRoute {
            VidurConversationRouter.route(text, context: busyDay, seed: 0, now: VidurTestClock.now,
                                          calendar: VidurTestClock.calendar)
        }
        if case .smallTalk = route("hello") {} else { XCTFail("hello should be small talk") }
        if case .command(.scheduleMeeting) = route("schedule a design review tomorrow at 4") {} else {
            XCTFail("expected a schedule command")
        }
        if case .reply = route("delete my meetings") {} else { XCTFail("expected an honest refusal") }
        XCTAssertEqual(route("what did we decide?"), .question("what did we decide?"))
        XCTAssertEqual(route("hey vidur what did we decide"), .question("what did we decide"))
    }

    func testSuggestionsFromRealData() {
        let list = VidurProactive.suggestions(for: busyDay, limit: 3, now: VidurTestClock.now, calendar: VidurTestClock.calendar)
        XCTAssertEqual(list.first, "What did we decide in the last Design review?")
        XCTAssertTrue(list.contains("What is overdue for me?"))
        XCTAssertLessThanOrEqual(list.count, 3)
        let fresh = VidurProactive.suggestions(for: VidurAssistantContext(), limit: 3, now: VidurTestClock.now,
                                               calendar: VidurTestClock.calendar)
        XCTAssertEqual(fresh, ["Schedule a meeting tomorrow at 10"])
    }

    func testFollowUpsSkipTheQuestionJustAsked() {
        let list = VidurProactive.followUps(after: .tasks, asked: "What did we decide?", context: VidurAssistantContext())
        XCTAssertFalse(list.contains("What did we decide?"))
        XCTAssertFalse(list.isEmpty)
    }

    func testConfirmationUnderstandsYesAndNo() {
        XCTAssertEqual(VidurConfirmation.answer(to: "Yes"), true)
        XCTAssertEqual(VidurConfirmation.answer(to: "yes, schedule it"), true)
        XCTAssertEqual(VidurConfirmation.answer(to: "haan kar do"), true)
        XCTAssertEqual(VidurConfirmation.answer(to: "No"), false)
        XCTAssertEqual(VidurConfirmation.answer(to: "cancel that"), false)
        XCTAssertNil(VidurConfirmation.answer(to: "what did we decide"))
    }
}