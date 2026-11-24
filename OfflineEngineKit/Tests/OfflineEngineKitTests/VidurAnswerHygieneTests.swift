import XCTest
@testable import OfflineEngineKit

/// What Vidur must never show again: ISO timestamps, "context blocks", doubled "Resolved:", junk decisions,
/// "20 number" when the minutes say "20 November", and answers that deny and affirm the same decision.
final class VidurAnswerHygieneTests: XCTestCase {
    private let calendar = VidurEvalFixtures.calendar

    private var kolkata: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return value
    }

    private func record(_ title: String, day: Int, summary: String = "", decisions: [String] = [],
                        tasks: [VidurMeetingTask] = [], turns: [VidurMeetingTurn] = []) -> VidurMeetingRecord {
        VidurMeetingRecord(
            title: title, date: VidurEvalFixtures.date(2025, 11, day, 10), attendees: ["Pawan", "Neha"],
            summary: summary, decisions: decisions.map { VidurMeetingLine(text: $0, timestamp: 5) },
            tasks: tasks, turns: turns)
    }

    private func ask(_ question: String, _ records: [VidurMeetingRecord]) -> VidurQuickAnswer {
        VidurQuickAnswerer.answer(question: question, records: records, history: [], selfNames: [],
                                  now: VidurEvalFixtures.now, calendar: calendar)
    }

    // MARK: Case 5. ISO timestamps

    func testIsoTimestampsBecomeNaturalDates() {
        XCTAssertEqual(VidurNaturalDates.rewrite("It needs to be tested by 2026-11-23T12:59:41Z.", calendar: calendar),
                       "It needs to be tested by Mon 23 Nov at 12:59 PM.")
        XCTAssertEqual(VidurNaturalDates.rewrite("Tested by 2026-11-23T12:59:41Z", calendar: kolkata),
                       "Tested by Mon 23 Nov at 6:29 PM")
        XCTAssertEqual(VidurNaturalDates.rewrite("Due 2026-11-23.", calendar: calendar), "Due 23 Nov.")
        XCTAssertEqual(VidurNaturalDates.rewrite("Due 2026-11-23T00:00:00Z", calendar: calendar), "Due 23 Nov")
        XCTAssertEqual(VidurNaturalDates.rewrite("At 2026-11-23 18:30 sharp", calendar: calendar),
                       "At Mon 23 Nov at 6:30 PM sharp")
        XCTAssertEqual(VidurNaturalDates.rewrite("Offset 2026-11-23T18:30:00+05:30", calendar: calendar),
                       "Offset Mon 23 Nov at 1:00 PM")
        XCTAssertEqual(VidurNaturalDates.rewrite("Two: 2026-11-23 and 2026-11-24.", calendar: calendar),
                       "Two: 23 Nov and 24 Nov.")
    }

    func testTextThatIsNotADateIsLeftAlone() {
        for text in ["Version 2026-13-45 is not a date", "Call 555-1234 today", "No dates here", "Room 2026-11-2300"] {
            XCTAssertEqual(VidurNaturalDates.rewrite(text, calendar: calendar), text)
        }
    }

    func testPolishWritesDatesNaturally() {
        let reply = "The login fix needs to be tested by 2026-11-23T12:59:41Z."
        let polished = VidurAnswerPolish.polish(reply, allowTask: true, calendar: calendar)
        XCTAssertEqual(polished, "The login fix needs to be tested by Mon 23 Nov at 12:59 PM.")
        XCTAssertFalse(polished.contains("2026-11-23T"))
    }

    func testQuickAnswersNeverShowIsoTimestamps() {
        let task = VidurMeetingTask(title: "Login fix needs to be tested by 2026-11-23T12:59:41Z", owner: "Neha", timestamp: 4)
        let answer = ask("What are Neha\u{2019}s tasks?", [record("Quick meeting", day: 22, tasks: [task])])
        XCTAssertTrue(answer.text.contains("Mon 23 Nov at 12:59 PM"), answer.text)
        XCTAssertFalse(answer.text.contains("2026-11-23T"), answer.text)
        XCTAssertEqual(answer.tasks.first?.title, "Login fix needs to be tested by Mon 23 Nov at 12:59 PM")
        for source in answer.sources { XCTAssertFalse(source.quote.contains("2026-11-23T"), source.quote) }
    }

    func testContextBlocksNeverShowIsoTimestamps() {
        let task = VidurMeetingTask(title: "Test the login fix by 2026-11-23T12:59:41Z", owner: "Neha", timestamp: 4)
        let meeting = record("Quick meeting", day: 22, summary: "The login fix must be tested by 2026-11-23T12:59:41Z.",
                             tasks: [task])
        let question = "What needs to be tested?"
        let retrieval = VidurRagTestSupport.retrieve(question, index: VidurRagTestSupport.index([meeting]))
        let input = VidurRagPromptInput(question: question, userName: "Neha", now: VidurEvalFixtures.now,
                                        calendar: calendar, retrieval: retrieval)
        let built = VidurRagPromptBuilder.build(input)
        XCTAssertFalse(built.user.contains("2026-11-23T"), built.user)
        XCTAssertTrue(built.user.contains("Mon 23 Nov at 12:59 PM"), built.user)
    }

    // MARK: Case 2. Internal words

    func testContextBlocksBecomeYourMeetings() {
        let reply = "The presentation ownership is not explicitly stated in the context blocks. "
            + "The summary mentions approving a $10,000 budget, but it does not specify who owns the presentation."
        let polished = VidurAnswerPolish.polish(reply, allowTask: true, calendar: calendar)
        XCTAssertTrue(polished.contains("not explicitly stated in your meetings."), polished)
        XCTAssertTrue(polished.contains("Your meetings mention approving a $10,000 budget"), polished)
        for word in ["context", "block", "The summary", "summary mentions"] {
            XCTAssertFalse(polished.contains(word), "\(word) in \(polished)")
        }
    }

    func testBlockSubjectsAndIdsAreRewrittenOrRemoved() {
        let polish: (String) -> String = { VidurAnswerPolish.polish($0, allowTask: true, calendar: self.calendar) }
        XCTAssertEqual(polish("The context blocks do not mention the budget."), "Your meetings do not mention the budget.")
        XCTAssertEqual(polish("Neha owns the quote (c1)."), "Neha owns the quote.")
        XCTAssertEqual(polish("Neha owns the quote [c1, c3]."), "Neha owns the quote.")
        XCTAssertEqual(polish("Pawan said so in block 3."), "Pawan said so.")
        XCTAssertEqual(polish("Nothing about this is in the provided context."), "Nothing about this is in your meetings.")
        XCTAssertEqual(polish("Based on the context blocks, Neha owns it."), "Based on your meetings, Neha owns it.")
    }

    func testSentencesThatOnlyTalkAboutBlocksAreDropped() {
        let polish: (String) -> String = { VidurAnswerPolish.polish($0, allowTask: true, calendar: self.calendar) }
        XCTAssertEqual(polish("Block 2 is a decision. Neha owns the quote (c1)."), "Neha owns the quote.")
        XCTAssertEqual(polish("Neha owns it. See c1 and c3."), "Neha owns it.")
        XCTAssertTrue(VidurLeakFilter.isBlockTalk("See c1 and c3."))
        XCTAssertFalse(VidurLeakFilter.isBlockTalk("Pawan asked Neha to send the presentation."))
    }

    func testOrdinaryWordsAreNotTouched() {
        let polish: (String) -> String = { VidurAnswerPolish.polish($0, allowTask: true, calendar: self.calendar) }
        let plain = "Pawan asked Neha to send the presentation on 22 Nov. The road was blocked, so the C level team joined late."
        XCTAssertEqual(polish(plain), plain)
    }

    func testSystemPromptForbidsInternalWords() {
        let built = promptFor("What did we decide on launch?")
        XCTAssertTrue(built.system.contains("Never say \"block\", \"context\", \"snippet\", \"the summary\""), built.system)
        XCTAssertTrue(built.system.contains("in your meetings"), built.system)
    }

    private func promptFor(_ question: String) -> VidurRagPrompt {
        let retrieval = VidurRagTestSupport.retrieve(question)
        let input = VidurRagPromptInput(question: question, userName: "Neha Sharma", now: VidurEvalFixtures.now,
                                        calendar: calendar, retrieval: retrieval)
        return VidurRagPromptBuilder.build(input)
    }

    // MARK: Case 3. Contradictions

    private let contradiction = "The budget discussion was not fully resolved. Pawan mentioned the need to discuss the budget, "
        + "but no decision was made. The budget was not approved, and the issue was to work on the website design "
        + "and approve a $10,000 budget."

    func testAnswerThatDeniesAndAffirmsTheSameSubjectIsFlagged() {
        XCTAssertEqual(VidurContradictionGuard.conflictingSubject(in: contradiction), "budget")
        XCTAssertNil(VidurContradictionGuard.conflictingSubject(in: "The budget is an open issue. Pawan raised it on 22 Nov."))
        XCTAssertNil(VidurContradictionGuard.conflictingSubject(in: "No decision was made on the vendor. The budget was approved."))
        XCTAssertNil(VidurContradictionGuard.conflictingSubject(in: "The budget was approved on 22 Nov."))
        XCTAssertNil(VidurContradictionGuard.conflictingSubject(in: "The budget was not decided."))
    }

    func testContradictionFallsBackToTheSavedOpenIssue() throws {
        let issue = VidurMeetingLine(text: "Budget is not decided", timestamp: 20, quote: "the budget is not yet decided",
                                     speaker: "Pawan")
        let meeting = VidurMeetingRecord(
            title: "Quick meeting", date: VidurEvalFixtures.date(2025, 11, 22, 10), attendees: ["Pawan", "Neha"],
            openIssues: [issue],
            turns: [VidurMeetingTurn(text: "the budget is not yet decided and that is pending", start: 20, speaker: "Pawan")])
        let retrieval = VidurRagTestSupport.retrieve("How did the budget discussion go?",
                                                     index: VidurRagTestSupport.index([meeting]))
        let fix = try XCTUnwrap(VidurContradictionGuard.fix(answer: contradiction, retrieval: retrieval, calendar: calendar))
        XCTAssertEqual(fix.text, "In Quick meeting (Sat 22 Nov), this is still an open issue: Budget is not decided.")
        XCTAssertEqual(fix.chunk.kind, .openIssue)
        XCTAssertNil(VidurContradictionGuard.fix(answer: "The budget is an open issue.", retrieval: retrieval, calendar: calendar))
    }

    func testContradictionFallsBackToTheSavedDecision() throws {
        let meeting = record("Launch sync", day: 10, decisions: ["Launch on 20 November"])
        let retrieval = VidurRagTestSupport.retrieve("How did the launch go?", index: VidurRagTestSupport.index([meeting]))
        let reply = "The launch was not decided. They will approve the launch on Friday."
        let fix = try XCTUnwrap(VidurContradictionGuard.fix(answer: reply, retrieval: retrieval, calendar: calendar))
        XCTAssertEqual(fix.text, "In Launch sync (Mon 10 Nov), the saved decision is: Launch on 20 November.")
    }

    // MARK: Case 4. Decisions

    func testDecisionPrefixesAreStrippedOnce() {
        XCTAssertEqual(VidurDecisionText.clean("Resolved: Resolved: The app should include charts."), "The app should include charts.")
        XCTAssertEqual(VidurDecisionText.clean("Decided: hire two designers"), "Hire two designers")
        XCTAssertEqual(VidurDecisionText.clean("RESOLVED THAT the launch moves to Friday"), "The launch moves to Friday")
        XCTAssertEqual(VidurDecisionText.clean("Decision - ship it on Monday"), "Ship it on Monday")
        XCTAssertEqual(VidurDecisionText.clean("Launch on 20 November"), "Launch on 20 November")
        XCTAssertEqual(VidurDecisionText.clean("Decision-making process changes"), "Decision-making process changes")
        XCTAssertEqual(VidurDecisionText.clean("Resolved:"), "Resolved:")
    }

    func testJunkDecisionsAreNotSubstantial() {
        XCTAssertFalse(VidurDecisionText.isSubstantial("Let her come."))
        XCTAssertFalse(VidurDecisionText.isSubstantial("Ok."))
        XCTAssertFalse(VidurDecisionText.isSubstantial("Launch Friday"))
        XCTAssertTrue(VidurDecisionText.isSubstantial("Launch on 20 November"))
        XCTAssertTrue(VidurDecisionText.isSubstantial("Go with the Pune vendor"))
        XCTAssertTrue(VidurDecisionText.isSubstantial("The app should include charts and graphs."))
    }

    func testMeetingRecordKeepsDecisionsWithoutALabel() {
        let meeting = record("Planning", day: 20, decisions: ["Resolved: Resolved: Launch on 20 November"])
        XCTAssertEqual(meeting.decisions.first?.text, "Launch on 20 November")
        let index = VidurRagTestSupport.index([meeting])
        XCTAssertTrue(index.chunks.contains { $0.kind == .decision && $0.text.hasPrefix("Decision: Launch on 20 November") })
        XCTAssertFalse(index.chunks.contains { $0.text.contains("Resolved") })
    }

    func testDecisionListHasNoDoubledLabelAndNoJunk() {
        let planning = record("Planning", day: 20, decisions: ["Resolved: Resolved: The app should include charts and graphs.",
                                                                 "Let her come."])
        let hiring = record("Hiring", day: 21, decisions: ["Decided: Hire two designers next quarter"])
        let vendors = record("Vendors", day: 19, decisions: ["Go with the Pune vendor"])
        let answer = ask("What did we decide?", [planning, hiring, vendors])
        XCTAssertEqual(answer.intent, .decisions)
        XCTAssertTrue(answer.text.hasPrefix("3 decisions across 3 meetings:"), answer.text)
        XCTAssertTrue(answer.text.contains("\u{2022} The app should include charts and graphs."), answer.text)
        XCTAssertTrue(answer.text.contains("\u{2022} Hire two designers next quarter"), answer.text)
        XCTAssertFalse(answer.text.contains("Resolved"), answer.text)
        XCTAssertFalse(answer.text.contains("Decided:"), answer.text)
        XCTAssertFalse(answer.text.contains("Let her come"), answer.text)
    }

    func testAMeetingWithOnlyJunkDecisionsListsNone() {
        let answer = ask("What did we decide?", [record("Planning", day: 20, decisions: ["Let her come."])])
        XCTAssertTrue(answer.text.contains("No decisions"), answer.text)
        XCTAssertFalse(answer.text.contains("Let her come"), answer.text)
    }

    // MARK: Case 6. "20 number"

    func testNumberBecomesTheMinutesMonthOnlyWhenTheMinutesSayIt() {
        let spoken = "they will launch this website on 20 number and also make sure to go with the pune vendor"
        XCTAssertEqual(VidurSpokenDates.prefer(spoken, minutes: ["The team plans a 20 November release."]),
                       "they will launch this website on 20 November and also make sure to go with the pune vendor")
        XCTAssertEqual(VidurSpokenDates.prefer(spoken, minutes: ["The team plans a 21 November release."]), spoken)
        XCTAssertEqual(VidurSpokenDates.prefer(spoken, minutes: []), spoken)
        XCTAssertEqual(VidurSpokenDates.prefer("on 20 number", minutes: ["Launch on 20 Nov"]), "on 20 Nov")
        XCTAssertEqual(VidurSpokenDates.prefer("on 5 number or 20 number", minutes: ["Ship 20 November"]), "on 5 number or 20 November")
        XCTAssertEqual(VidurSpokenDates.prefer("Pick a number", minutes: ["20 November"]), "Pick a number")
    }

    private let launchLine = "kalta and we will launch this website on 20 number and also make sure to go with the pune vendor and"

    func testQuickAnswerUsesTheMinutesWordingForTheDate() {
        let turns = [VidurMeetingTurn(text: launchLine, start: 9, speaker: "Pawan")]
        let withMinutes = record("Quick meeting", day: 22, summary: "Planned for 20 November.", turns: turns)
        let answer = ask("What did we decide about the launch?", [withMinutes])
        XCTAssertTrue(answer.text.contains("launch this website on 20 November and also"), answer.text)
        XCTAssertFalse(answer.text.contains("20 number"), answer.text)

        let withoutMinutes = record("Quick meeting", day: 22, turns: turns)
        let plain = ask("What did we decide about the launch?", [withoutMinutes])
        XCTAssertTrue(plain.text.contains("20 number"), "Kept as spoken: \(plain.text)")
    }

    func testPromptShowsTheMinutesWordingNextToATranscriptLine() {
        let turns = [VidurMeetingTurn(text: launchLine, start: 9, speaker: "Pawan")]
        let meeting = record("Quick meeting", day: 22, summary: "Planned for 20 November.", decisions: ["Launch on 20 November"],
                             turns: turns)
        let question = "What did we decide about the launch?"
        let retrieval = VidurRagTestSupport.retrieve(question, index: VidurRagTestSupport.index([meeting]))
        let input = VidurRagPromptInput(question: question, userName: "Neha", now: VidurEvalFixtures.now,
                                        calendar: calendar, retrieval: retrieval)
        let built = VidurRagPromptBuilder.build(input)
        XCTAssertFalse(built.user.contains("20 number"), built.user)
        XCTAssertTrue(built.user.contains("on 20 November and also make sure"), built.user)
    }
}
