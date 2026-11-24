import XCTest
@testable import OfflineEngineKit

/// The pure parts of Vidur's chat: greeting, insight, suggestions, answer length, honest fallbacks, answer rows,
/// follow-up resolution and the latency log line.
final class VidurExperienceTests: XCTestCase {
    private let calendar = VidurTestClock.calendar

    private func at(_ hour: Int) -> Date { VidurTestClock.date(2025, 3, 12, hour, 0) }

    private var busyDay: VidurAssistantContext {
        VidurAssistantContext(
            userName: "Arjun Mehta",
            upcomingToday: [VidurMeetingBrief(title: "Design review", start: VidurTestClock.date(2025, 3, 12, 11, 0))],
            nextMeeting: VidurMeetingBrief(title: "Design review", start: VidurTestClock.date(2025, 3, 12, 11, 0)),
            nextMeetingHasHistory: true, overdueActionCount: 1, openActionCount: 5, unreviewedSuggestionCount: 0,
            lastMeetingTitle: "Launch planning", lastMeetingHasMinutes: true, isRecording: false,
            hasAnyMeetings: true, dueTodayActionCount: 2)
    }

    // MARK: Greeting and insight

    func testGreetingFollowsTheTimeOfDayAndUsesTheFirstName() {
        XCTAssertEqual(VidurGreeting.title(for: busyDay, now: at(8), calendar: calendar), "Good morning, Arjun")
        XCTAssertEqual(VidurGreeting.title(for: busyDay, now: at(14), calendar: calendar), "Good afternoon, Arjun")
        XCTAssertEqual(VidurGreeting.title(for: busyDay, now: at(19), calendar: calendar), "Good evening, Arjun")
        XCTAssertEqual(VidurGreeting.title(for: busyDay, now: at(2), calendar: calendar), "Hello, Arjun")
        XCTAssertEqual(VidurGreeting.title(for: VidurAssistantContext(), now: at(8), calendar: calendar), "Good morning")
    }

    func testInsightNamesWhatNeedsAttentionFirst() {
        XCTAssertEqual(VidurInsight.line(for: busyDay, now: at(9), calendar: calendar),
                       "2 actions are due today and 1 is overdue.")
        var overdueOnly = busyDay
        overdueOnly.dueTodayActionCount = 0
        overdueOnly.overdueActionCount = 3
        XCTAssertEqual(VidurInsight.line(for: overdueOnly, now: at(9), calendar: calendar), "3 actions are overdue.")
        var single = busyDay
        single.overdueActionCount = 0
        single.dueTodayActionCount = 1
        XCTAssertEqual(VidurInsight.line(for: single, now: at(9), calendar: calendar), "1 action is due today.")
    }

    func testInsightFallsBackToTheNextMeetingAndStaysQuietWhenThereIsNothing() {
        var calm = busyDay
        calm.dueTodayActionCount = 0
        calm.overdueActionCount = 0
        XCTAssertEqual(VidurInsight.line(for: calm, now: at(9), calendar: calendar), "Design review starts at 11:00 AM.")
        // A meeting more than three hours away is not worth a headline.
        XCTAssertNil(VidurInsight.line(for: calm, now: at(1), calendar: calendar))
        XCTAssertNil(VidurInsight.line(for: VidurAssistantContext(), now: at(9), calendar: calendar))
        var recording = busyDay
        recording.isRecording = true
        XCTAssertNil(VidurInsight.line(for: recording, now: at(9), calendar: calendar))
    }

    // MARK: Suggestions

    func testSmartSuggestionsComeFromRealData() {
        let list = VidurProactive.smartSuggestions(for: busyDay, limit: 4, now: at(9), calendar: calendar)
        XCTAssertEqual(list.map(\.text), [
            "What did we decide in the last Design review?", "What is overdue for me?", "What is due today?",
            "Summarize the last meeting"
        ])
        XCTAssertTrue(list.allSatisfy { !$0.symbol.isEmpty })
    }

    func testSmartSuggestionsForEmptyAndRecordingStates() {
        let fresh = VidurProactive.smartSuggestions(for: VidurAssistantContext(), now: at(9), calendar: calendar)
        XCTAssertEqual(fresh.map(\.text), ["Schedule a meeting tomorrow at 10"])
        let recording = VidurProactive.smartSuggestions(for: VidurAssistantContext(isRecording: true), now: at(9),
                                                        calendar: calendar)
        XCTAssertEqual(recording.map(\.text), ["What did we decide?", "Which tasks are still open?"])
        let limited = VidurProactive.smartSuggestions(for: busyDay, limit: 2, now: at(9), calendar: calendar)
        XCTAssertEqual(limited.count, 2)
    }

    // MARK: Answer length

    func testFactsAreOneSentenceAndOverviewsAreFewSentences() {
        XCTAssertEqual(VidurAnswerShape.of("Who owns the budget task?"), .fact)
        XCTAssertEqual(VidurAnswerShape.of("What did we decide on launch?"), .fact)
        XCTAssertEqual(VidurAnswerShape.of("How did the launch discussion go?"), .overview)
        XCTAssertEqual(VidurAnswerShape.of("Summarize the last meeting"), .overview)
        XCTAssertEqual(VidurAnswerShape.of("What were the main concerns?"), .overview)
        XCTAssertTrue(VidurAnswerShape.fact.promptRule.contains("One short sentence"))
        XCTAssertTrue(VidurAnswerShape.overview.promptRule.contains("3 to 4"))
    }

    func testThePromptCarriesTheLengthRuleAndTheFollowUpRule() {
        func system(_ question: String) -> String {
            let retrieval = VidurRagTestSupport.retrieve(question)
            return VidurRagPromptBuilder.build(VidurRagPromptInput(
                question: question, userName: "Neha Sharma", now: VidurEvalFixtures.now,
                calendar: VidurEvalFixtures.calendar, retrieval: retrieval)).system
        }
        XCTAssertTrue(system("What did we decide on launch?").contains("One short sentence for a plain fact"))
        XCTAssertTrue(system("How did the launch discussion go?").contains("3 to 4 short sentences"))
        XCTAssertTrue(system("What did we decide on launch?").contains("Resolve \"it\""))
    }

    // MARK: Follow-ups

    func testAFollowUpLikeAndWhoOwnsItResolvesFromThePreviousQuestion() {
        let history = [VidurChatTurn(question: "Which tasks are still open?", answer: "4 open tasks across 3 meetings.")]
        let answer = VidurQuickAnswerer.answer(question: "and who owns it?", records: VidurEvalFixtures.all, history: history,
                                               selfNames: VidurEvalFixtures.selfNames, now: VidurEvalFixtures.now,
                                               calendar: VidurEvalFixtures.calendar)
        XCTAssertNotEqual(answer.confidence, .notFound, answer.text)
        XCTAssertEqual(answer.intent, .tasks)
        XCTAssertTrue(answer.tasks.contains { $0.owner != nil }, "The follow-up lists tasks with their owners")
    }

    func testAShortFollowUpKeepsTheLanguageOfTheQuestionBeforeIt() {
        let history = [VidurChatTurn(question: "Launch ke baare mein kya tay hua?", answer: "Launch 20 November ko hoga.")]
        XCTAssertEqual(VidurRagPromptBuilder.resolveLanguage(question: "and Neha?", history: history), .hinglish)
        XCTAssertEqual(VidurRagPromptBuilder.resolveLanguage(question: "and Neha?", history: []), .english)
    }

    // MARK: Fallback wording

    func testNotFoundIsHonestAndOffersSomethingToTry() {
        let text = VidurFallback.notFound(
            base: "I couldn\u{2019}t find anything about \u{201C}pricing\u{201D} in your meetings.",
            suggestions: ["What did we decide?", "Which tasks are still open?", "Summarize the last meeting"],
            language: .english)
        XCTAssertTrue(text.hasPrefix("I couldn\u{2019}t find anything about"), text)
        XCTAssertTrue(text.contains("Try asking \u{201C}What did we decide?\u{201D} or \u{201C}Which tasks are still open?\u{201D}."), text)
        XCTAssertFalse(text.contains("Summarize"), "Two ideas at most")
    }

    func testModelNotDiscussedSentenceBecomesThePlainMissWording() {
        let text = VidurFallback.notFound(base: VidurGroundedPrompt.notDiscussedEnglish,
                                          suggestions: ["What did we decide?"], language: .english)
        XCTAssertEqual(text, "I couldn\u{2019}t find that in your meetings. Try asking \u{201C}What did we decide?\u{201D}.")
    }

    func testNotFoundSpeaksHinglishWhenAskedInHinglish() {
        let text = VidurFallback.notFound(base: VidurGroundedPrompt.notDiscussedHinglish,
                                          suggestions: ["What did we decide?", "Which tasks are still open?"],
                                          language: .hinglish)
        XCTAssertTrue(text.hasPrefix(VidurGroundedPrompt.notDiscussedHinglish), text)
        XCTAssertTrue(text.contains("Aap yeh puch sakte hain:"), text)
        XCTAssertTrue(text.contains(" ya "), text)
    }

    func testOtherAnswersAreNeverChangedByTheFallback() {
        let facts = "Launch moves to Tuesday 18 November."
        XCTAssertEqual(VidurFallback.notFound(base: facts, suggestions: ["What did we decide?"], language: .english), facts)
        let empty = "You have no saved meetings with minutes or a transcript yet."
        XCTAssertEqual(VidurFallback.notFound(base: empty, suggestions: ["What did we decide?"], language: .english), empty)
        let already = "I couldn\u{2019}t find that. Try asking about launch."
        XCTAssertEqual(VidurFallback.notFound(base: already, suggestions: ["What did we decide?"], language: .english), already)
        XCTAssertEqual(VidurFallback.notFound(base: "I couldn\u{2019}t find that in your meetings.", suggestions: [],
                                              language: .english), "I couldn\u{2019}t find that in your meetings.")
    }

    // MARK: Answer rows

    func testBulletedAnswersSplitIntoRows() {
        let layout = VidurAnswerLayout.parse("2 decisions in Launch readiness:\n\u{2022} Launch on 20 November\n\u{2022} Go with the Pune vendor")
        XCTAssertEqual(layout.intro, "2 decisions in Launch readiness:")
        XCTAssertEqual(layout.bullets, ["Launch on 20 November", "Go with the Pune vendor"])
        XCTAssertEqual(layout.outro, "")
        let more = VidurAnswerLayout.parse("3 tasks:\n\u{2022} A\n\u{2022} B\n\u{2026}and 1 more.")
        XCTAssertEqual(more.bullets, ["A", "B"])
        XCTAssertEqual(more.outro, "\u{2026}and 1 more.")
    }

    func testPlainTextAndASingleBulletStayText() {
        let plain = "Launch moves to Tuesday."
        XCTAssertEqual(VidurAnswerLayout.parse(plain), VidurAnswerLayout(intro: plain, bullets: [], outro: ""))
        let single = "1 decision:\n\u{2022} Launch on 20 November"
        XCTAssertEqual(VidurAnswerLayout.parse(single).bullets, [])
        XCTAssertEqual(VidurAnswerLayout.parse(single).intro, single)
    }

    // MARK: Latency

    func testLatencyLineHasNoContent() {
        XCTAssertEqual(VidurLatency.line(tier: "generated", firstTokenMs: 3120, totalMs: 5480),
                       "Vidur answer tier=generated first_token_ms=3120 total_ms=5480")
        XCTAssertEqual(VidurLatency.line(tier: "structured", firstTokenMs: nil, totalMs: 12),
                       "Vidur answer tier=structured first_token_ms=-1 total_ms=12")
    }
}
