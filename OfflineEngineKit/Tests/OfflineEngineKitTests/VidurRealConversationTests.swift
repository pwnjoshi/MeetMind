import XCTest
@testable import OfflineEngineKit

/// A conversation recorded on a real iPhone: a scheduled meeting that never happened, and two "Quick meeting"
/// recordings with noisy English speech recognition. Vidur has to answer plainly, never paste transcript
/// lines, never show "Speaker 1", and be honest when nothing was saved.
final class VidurRealConversationTests: XCTestCase {
    private let scheduledID = UUID()
    private let firstID = UUID()
    private let secondID = UUID()

    private let launchLine = "kalta and we will launch this website on 20 number and also make sure to go with the pune vendor and"
    private let presentationLine = "uh prepare the agenda power by friday and send the neha you send the presentation please uh"

    /// A scheduled meeting. It has attendees and nothing else.
    private var scheduled: VidurMeetingRecord {
        VidurMeetingRecord(id: scheduledID, title: "Scheduled Meeting - 23 Nov 2026 at 11:36AM",
                           date: VidurEvalFixtures.date(2025, 11, 23, 11), attendees: ["Pawan", "Neha"])
    }

    /// 22 Nov. The agenda task belongs to Pawan, the budget is an open issue, and there is no decision.
    private func first(decisions: [VidurMeetingLine] = [], extraTasks: [VidurMeetingTask] = []) -> VidurMeetingRecord {
        let agenda = VidurMeetingTask(title: "Send the agenda", owner: "Pawan", timestamp: 3, quote: "prepare the agenda")
        return VidurMeetingRecord(
            id: firstID, title: "Quick meeting", date: VidurEvalFixtures.date(2025, 11, 22, 10),
            attendees: ["Pawan", "Neha"], decisions: decisions,
            openIssues: [VidurMeetingLine(text: "Budget is not decided", timestamp: 20,
                                          quote: "the budget is not yet decided", speaker: "Pawan")],
            tasks: [agenda] + extraTasks,
            turns: [
                VidurMeetingTurn(text: presentationLine, start: 3, speaker: "Pawan"),
                VidurMeetingTurn(text: launchLine, start: 9, speaker: "Pawan"),
                VidurMeetingTurn(text: "the budget is not yet decided and that is pending", start: 20, speaker: "Pawan")
            ])
    }

    /// 23 Nov. Only a transcript, and the voice was never named.
    private var second: VidurMeetingRecord {
        VidurMeetingRecord(
            id: secondID, title: "Quick meeting", date: VidurEvalFixtures.date(2025, 11, 23, 9),
            turns: [VidurMeetingTurn(text: "And, individual presentation.", start: 83, speaker: "Speaker 1")])
    }

    private var everything: [VidurMeetingRecord] { [scheduled, first(), second] }

    private func ask(_ question: String, in records: [VidurMeetingRecord], history: [VidurChatTurn] = [],
                     current: UUID? = nil) -> VidurQuickAnswer {
        VidurQuickAnswerer.answer(question: question, records: records, history: history, selfNames: [],
                                  now: VidurEvalFixtures.now, calendar: VidurEvalFixtures.calendar,
                                  currentMeetingID: current)
    }

    private func assertClean(_ answer: VidurQuickAnswer, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(answer.text.contains("Speaker 1"), answer.text, file: file, line: line)
        XCTAssertFalse(answer.text.contains("\u{201C}"), "No pasted quote: \(answer.text)", file: file, line: line)
        for source in answer.sources {
            XCTAssertNotEqual(source.speaker, "Speaker 1", file: file, line: line)
            XCTAssertNotEqual(source.speaker, "Someone", file: file, line: line)
        }
    }

    // MARK: A. A scheduled meeting that has not happened

    func testScheduledMeetingIsUnrecordedAndNamedAsThisMeeting() {
        XCTAssertTrue(VidurScopeNote.isUnrecorded([scheduled]))
        XCTAssertFalse(VidurScopeNote.isUnrecorded([scheduled, first()]))
        let decision = ask("What did we decide about the launch?", in: [scheduled], current: scheduledID)
        XCTAssertTrue(decision.foundNothing)
        XCTAssertTrue(decision.text.contains("this meeting"), decision.text)
        XCTAssertFalse(decision.text.contains("Scheduled Meeting"), decision.text)

        let tasks = ask("What are Pawan\u{2019}s task?", in: [scheduled], current: scheduledID)
        XCTAssertEqual(tasks.text, "Pawan has no open tasks in this meeting.")
        XCTAssertTrue(tasks.foundNothing)

        let budget = ask("How did the budget discussion go?", in: [scheduled], current: scheduledID)
        XCTAssertTrue(budget.foundNothing)
        XCTAssertFalse(budget.text.contains("Scheduled Meeting"), budget.text)
    }

    // MARK: B. All meetings

    func testDecisionQuestionWithNoSavedDecisionSaysSoAndParaphrasesTheTranscript() {
        let answer = ask("What did we decide about the launch?", in: everything)
        XCTAssertEqual(answer.intent, .topic)
        XCTAssertTrue(answer.text.contains("no recorded decision about launch"), answer.text)
        XCTAssertTrue(answer.text.contains("Pawan said that they will launch this website"), answer.text)
        XCTAssertTrue(answer.text.contains("pune vendor"), answer.text)
        XCTAssertTrue(answer.text.contains("22 Nov"), answer.text)
        XCTAssertFalse(answer.text.hasSuffix("and."), "A dangling conjunction is dropped: \(answer.text)")
        XCTAssertFalse(answer.text.contains("kalta"), "The garbled start is dropped: \(answer.text)")
        XCTAssertEqual(answer.confidence, .partial)
        XCTAssertEqual(answer.sources.first?.speaker, "Pawan")
        assertClean(answer)
    }

    func testDecisionSavedInTheMinutesIsFoundAcrossMeetings() {
        let saved = VidurMeetingLine(text: "Launch on 20 November", timestamp: 9, quote: "we will launch on 20 November",
                                     speaker: "Pawan")
        let records = [scheduled, first(decisions: [saved]), second]
        let answer = ask("What did we decide about the launch?", in: records)
        XCTAssertEqual(answer.intent, .decisions)
        XCTAssertEqual(answer.confidence, .complete)
        XCTAssertTrue(answer.text.contains("Launch on 20 November"), answer.text)
        XCTAssertFalse(answer.text.contains("no recorded decision"), answer.text)
    }

    func testTaskQuestionsToleratTypingMistakes() {
        for question in ["What R Pawan task", "What are Pawan\u{2019}s task?", "Whats Pawans task?", "what are pawan's tasks"] {
            let answer = ask(question, in: everything)
            XCTAssertTrue(answer.text.contains("Pawan has 1 open task"), "\(question) -> \(answer.text)")
            XCTAssertTrue(answer.text.contains("Send the agenda"), answer.text)
            XCTAssertEqual(answer.confidence, .complete, question)
        }
    }

    func testUndecidedBudgetIsAnOpenIssueNeverATask() {
        let answer = ask("How did the budget discussion go?", in: everything)
        let lowered = answer.text.lowercased()
        XCTAssertTrue(lowered.contains("open issue") || lowered.contains("not yet decided"), answer.text)
        XCTAssertFalse(lowered.contains("task"), answer.text)
        assertClean(answer)
    }

    func testWhoOwnsWithoutASavedActionNamesThePersonWhoWasAsked() {
        let history = [VidurChatTurn(question: "How did the budget discussion go?", answer: "The budget is an open issue.")]
        let answer = ask("And who owns the presentation?", in: everything, history: history)
        XCTAssertTrue(answer.text.contains("No saved action covers presentation"), answer.text)
        XCTAssertTrue(answer.text.contains("Pawan asked Neha to send the presentation"), answer.text)
        XCTAssertTrue(answer.text.contains("22 Nov"), answer.text)
        XCTAssertEqual(answer.sources.first?.speaker, "Pawan")
        // A request found in the transcript is a deterministic owner answer, so the model is never asked.
        XCTAssertEqual(answer.intent, .tasks)
        XCTAssertEqual(answer.confidence, .complete)
        assertClean(answer)
    }

    func testOwnerQuestionsAreRecognisedIncludingFollowUps() {
        let owner = ["And who owns the presentation?", "who is responsible for the presentation?",
                     "Who\u{2019}s responsible for it?", "Whose task is the agenda?", "who will do the quote?",
                     "Who has to send the deck?", "and who has to do it", "Who owned the budget?"]
        for question in owner { XCTAssertTrue(VidurRagRouting.isOwnerQuestion(question), question) }
        let other = ["How did the budget discussion go?", "What did we decide?", "Who attended?", "Which tasks are open?",
                     "Who said the budget is pending?"]
        for question in other { XCTAssertFalse(VidurRagRouting.isOwnerQuestion(question), question) }
    }

    func testEveryOwnerPhrasingFindsThePersonWhoWasAsked() {
        let questions = ["Who is responsible for the presentation?", "Whose task is the presentation?",
                         "Who will do the presentation?", "Who has to do the presentation?", "and who owns the presentation"]
        for question in questions {
            let answer = ask(question, in: everything)
            XCTAssertTrue(answer.text.contains("Pawan asked Neha to send the presentation"), "\(question) -> \(answer.text)")
            XCTAssertEqual(answer.intent, .tasks, question)
            XCTAssertEqual(answer.confidence, .complete, question)
            assertClean(answer)
        }
    }

    func testRequestDetectionToleratesSpeechNoise() {
        let index = VidurPersonIndex(names: ["Pawan", "Neha"])
        let keys = Set(VidurScript.keys(forWord: "presentation"))
        let noisy = VidurGist.request(in: presentationLine, topicKeys: keys, speaker: "Pawan", index: index)
        XCTAssertEqual(noisy?.person.canonical, "Neha")
        XCTAssertEqual(noisy?.phrase, "send the presentation")
        let after = VidurGist.request(in: "please send the presentation to neha today", topicKeys: keys, speaker: "Pawan", index: index)
        XCTAssertEqual(after?.person.canonical, "Neha")
        XCTAssertEqual(after?.phrase, "send the presentation")
        let far = "neha is on leave and the weather is nice today and he said send the presentation"
        XCTAssertNil(VidurGist.request(in: far, topicKeys: keys, speaker: "Pawan", index: index))
        XCTAssertNil(VidurGist.request(in: "pawan will send the presentation", topicKeys: keys, speaker: "Pawan", index: index))
    }

    func testWhoOwnsWithATypoStillFindsThePerson() {
        let answer = ask("And who owns thevpresentation?", in: everything)
        XCTAssertTrue(answer.text.contains("Pawan asked Neha to send the presentation"), answer.text)
        assertClean(answer)
    }

    func testWhoOwnsFindsASavedActionByStemmedObject() {
        let due = VidurEvalFixtures.date(2025, 11, 28, 17)
        let action = VidurMeetingTask(title: "Send the presentation", owner: "Neha", dueDate: due, timestamp: 30)
        let records = [scheduled, first(extraTasks: [action]), second]
        for question in ["Who owns the presentation?", "who owns the presentations?"] {
            let answer = ask(question, in: records)
            XCTAssertEqual(answer.text, "Neha \u{2014} Send the presentation (due Fri 28 Nov)", question)
            XCTAssertEqual(answer.people, ["Neha"])
            XCTAssertEqual(answer.tasks.first?.title, "Send the presentation")
        }
    }

    func testAnonymousSpeakersNeverAppearInAnswersOrSources() {
        let questions = [
            "What did we say about the presentation?", "individual presentation", "Who said individual?",
            "What was said in the other quick meeting?"
        ]
        for question in questions {
            let answer = ask(question, in: everything)
            XCTAssertFalse(answer.text.contains("Speaker 1"), "\(question) -> \(answer.text)")
            XCTAssertFalse(answer.text.contains("Speaker"), "\(question) -> \(answer.text)")
            for source in answer.sources { XCTAssertNotEqual(source.speaker, "Speaker 1") }
        }
        let lone = ask("What was said about individual?", in: [second])
        XCTAssertTrue(lone.text.lowercased().contains("someone"), lone.text)
        XCTAssertFalse(lone.text.contains("Speaker"), lone.text)
    }

    // MARK: Typing mistakes

    func testNormalizerRepairsGluedWordsShorthandAndOneLetterTypos() {
        let records = everything
        XCTAssertEqual(VidurQuestionNormalizer.normalize("And who owns thevpresentation?", records: records),
                       "And who owns the presentation?")
        XCTAssertEqual(VidurQuestionNormalizer.normalize("What R Pawan task", records: records), "What are Pawan task")
        XCTAssertEqual(VidurQuestionNormalizer.normalize("whatdid we decide about the launch?", records: records),
                       "what did we decide about the launch?")
        XCTAssertEqual(VidurQuestionNormalizer.normalize("Whats Pawans task?", records: records), "Whats Pawan task?")
        XCTAssertEqual(VidurQuestionNormalizer.normalize("Who owns the presentaton?", records: records),
                       "Who owns the presentation?")
        XCTAssertEqual(VidurQuestionNormalizer.normalize("What are Pawan\u{2019}s tasks?", records: records),
                       "What are Pawan's tasks?")
    }

    func testNormalizerLeavesGoodQuestionsAlone() {
        let question = "What did we decide about the Mars rover?"
        XCTAssertEqual(VidurQuestionNormalizer.normalize(question, records: everything), question)
    }

    func testOneEditDistance() {
        XCTAssertTrue(VidurQuestionNormalizer.withinOneEdit("presentaton", "presentation"))
        XCTAssertTrue(VidurQuestionNormalizer.withinOneEdit("pawans", "pawan"))
        XCTAssertTrue(VidurQuestionNormalizer.withinOneEdit("launhc", "launch"))
        XCTAssertTrue(VidurQuestionNormalizer.withinOneEdit("vendar", "vendor"))
        XCTAssertFalse(VidurQuestionNormalizer.withinOneEdit("vendor", "vendor"))
        XCTAssertFalse(VidurQuestionNormalizer.withinOneEdit("budget", "bucket list"))
        XCTAssertFalse(VidurQuestionNormalizer.withinOneEdit("plan", "plans and"))
    }

    // MARK: Wording

    func testGistKeepsOnlyWhatWasSaidAndSwitchesPronouns() {
        let names = Set<String>(["pawan", "neha"])
        XCTAssertEqual(VidurGist.clause(from: "uh we should um hire two backend engineers next quarter.", topicKeys: [], names: names),
                       "they should hire two backend engineers next quarter")
        XCTAssertEqual(VidurGist.clause(from: "I will send the revised quote by Friday.", topicKeys: [], names: names),
                       "they will send the revised quote by Friday")
        XCTAssertEqual(VidurGist.clause(from: "I am sending it to Neha today", topicKeys: [], names: names),
                       "they are sending it to Neha today")
        XCTAssertNil(VidurGist.clause(from: "you send the presentation please", topicKeys: [], names: names))
        XCTAssertNil(VidurGist.clause(from: "ok", topicKeys: [], names: names))
        XCTAssertNil(VidurGist.clause(from: "\u{0935}\u{0947}\u{0902}\u{0921}\u{0930} \u{092A}\u{0947}\u{092E}\u{0947}\u{0902}\u{091F} \u{0915}\u{0930}\u{0928}\u{093E} \u{0939}\u{0948}",
                                      topicKeys: [], names: names))
    }

    func testPolishTurnsTaskIntoIssueAndHidesSpeakerLabels() {
        let reply = "Speaker 1 mentioned the budget was not yet decided and that it was a pending task. The budget task is open."
        let polished = VidurAnswerPolish.polish(reply, allowTask: false)
        XCTAssertFalse(polished.lowercased().contains("task"), polished)
        XCTAssertTrue(polished.hasPrefix("Someone mentioned"), polished)
        XCTAssertTrue(polished.contains("an open issue"), polished)
        XCTAssertTrue(polished.contains("The budget issue is open."), polished)
        let kept = VidurAnswerPolish.polish("Neha owns the task.", allowTask: true)
        XCTAssertEqual(kept, "Neha owns the task.")
    }

    func testChipSpeakerHidesAnonymousLabels() {
        XCTAssertNil(VidurAnswerPolish.chipSpeaker("Speaker 1"))
        XCTAssertNil(VidurAnswerPolish.chipSpeaker("S2"))
        XCTAssertNil(VidurAnswerPolish.chipSpeaker("Someone"))
        XCTAssertNil(VidurAnswerPolish.chipSpeaker("Note"))
        XCTAssertNil(VidurAnswerPolish.chipSpeaker(nil))
        XCTAssertEqual(VidurAnswerPolish.chipSpeaker("Pawan"), "Pawan")
    }
}
