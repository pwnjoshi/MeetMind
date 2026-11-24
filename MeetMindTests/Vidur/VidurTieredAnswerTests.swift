import XCTest
import Foundation
import OfflineEngineKit
@testable import MeetMind

private final class UpdateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [VidurAnswerUpdate] = []
    func add(_ update: VidurAnswerUpdate) { lock.lock(); stored.append(update); lock.unlock() }
    var updates: [VidurAnswerUpdate] { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

final class VidurMeetingFactsTests: XCTestCase {
    func testEvidenceParsingMatchesStoredFormat() {
        XCTAssertEqual(VidurMeetingFacts.parseEvidence("[01:05] send it").timestamp, 65)
        XCTAssertEqual(VidurMeetingFacts.parseEvidence("[01:05] send it").quote, "send it")
        XCTAssertEqual(VidurMeetingFacts.parseEvidence("[1:02:03] x").timestamp, 3723)
        XCTAssertNil(VidurMeetingFacts.parseEvidence("plain quote").timestamp)
        XCTAssertEqual(VidurMeetingFacts.parseEvidence("plain quote").quote, "plain quote")
        XCTAssertNil(VidurMeetingFacts.parseEvidence(nil).quote)
    }

    func testAgendaLineCleaning() {
        XCTAssertEqual(VidurMeetingFacts.cleanAgendaLine("1. Budget"), "Budget")
        XCTAssertEqual(VidurMeetingFacts.cleanAgendaLine("- Roadmap"), "Roadmap")
        XCTAssertEqual(VidurMeetingFacts.cleanAgendaLine("2026 budget"), "2026 budget")
    }
}

private final class InputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [VidurRefineInput] = []
    func add(_ input: VidurRefineInput) { lock.lock(); stored.append(input); lock.unlock() }
    var inputs: [VidurRefineInput] { lock.lock(); defer { lock.unlock() }; return stored }
}

final class VidurTieredFlowTests: XCTestCase {
    private let meetingID = UUID()

    private var sources: [VidurSourceMeeting] {
        [VidurSourceMeeting(id: meetingID, title: "Weekly sync", date: Date(), turns: [
            VidurSourceTurn(text: "Pricing page launch moves to Friday because legal review is pending", start: 12, end: 18, speaker: "Asha"),
            VidurSourceTurn(text: "Rahul will send the revised quote tomorrow", start: 30, end: 35, speaker: "Asha")
        ])]
    }

    private var facts: VidurMeetingFacts {
        VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(), attendees: ["Rahul", "Asha"],
                          absent: [], attendanceRecorded: true)
    }

    private var populatedFacts: VidurMeetingFacts {
        VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(), attendees: ["Rahul", "Asha"], absent: ["Meera"],
                          attendanceRecorded: true)
    }

    private func hooks(counter: CallCounter, available: Bool = true, fail: Bool = false, delay: TimeInterval = 0,
                       timeout: TimeInterval = 8, inputs: InputBox? = nil,
                       reply: VidurAnswer = VidurAnswer(text: "Moved to Friday.", kind: .generated)) -> VidurTieredHooks {
        VidurTieredHooks(
            refinementAvailable: { available },
            refineTimeout: timeout,
            refine: { input in
                counter.increment()
                inputs?.add(input)
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                if fail { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "model busy"]) }
                return reply
            })
    }

    private func run(_ question: String, facts: VidurMeetingFacts?, allow: Bool = true, additional: [VidurMeetingFacts] = [],
                     history: [VidurChatTurn] = [], userDisabled: Bool = false,
                     hooks: VidurTieredHooks) async -> [VidurAnswerUpdate] {
        let box = UpdateBox()
        let request = VidurTieredRequest(question: question, sources: sources, facts: facts, length: .standard,
                                         allowRefinement: allow, additionalFacts: additional, history: history,
                                         userDisabledRefinement: userDisabled)
        await VidurTieredAnswerService.run(request, hooks: hooks) { box.add($0) }
        return box.updates
    }

    private let unmatched = "Which cloud provider hosts database backups?"
    private let reasoning = "Why does the pricing page launch move to Friday?"

    func testMinutesAnswerIsFinalAndSkipsTheModel() async {
        let counter = CallCounter()
        let updates = await run("Who attended?", facts: populatedFacts, hooks: hooks(counter: counter))
        XCTAssertEqual(counter.count, 0, "Saved minutes answer fully, so no model runs")
        XCTAssertEqual(updates.map(\.stage), [.final])
        XCTAssertEqual(updates[0].tier, .structured)
        XCTAssertTrue(updates[0].answer?.text.contains("Present (2)") == true)
        XCTAssertTrue(updates[0].answer?.text.contains("Meera") == true)
    }

    func testTranscriptQuestionIsAnsweredInstantlyWithASourceAndNoModel() async {
        let counter = CallCounter()
        let started = Date()
        let updates = await run("When does the pricing page launch?", facts: facts, hooks: hooks(counter: counter))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(updates.map(\.stage), [.final])
        XCTAssertEqual(updates[0].tier, .quote)
        let answer = updates[0].answer
        XCTAssertTrue(answer?.text.contains("Friday") == true)
        XCTAssertEqual(answer?.citations.first?.timecode, "00:12")
        XCTAssertEqual(answer?.citations.first?.meetingID, meetingID)
        XCTAssertEqual(answer?.citations.first?.speaker, "Asha")
        XCTAssertEqual(answer?.kind, .extractive)
    }

    func testReasoningQuestionShowsTheQuickAnswerThenTheModelAnswer() async {
        let counter = CallCounter()
        let updates = await run(reasoning, facts: facts, hooks: hooks(counter: counter))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(updates.map(\.stage), [.refining, .final])
        XCTAssertNotNil(updates[0].answer, "The quick answer stays visible while the model thinks")
        XCTAssertEqual(updates[1].tier, .generated)
        XCTAssertEqual(updates[1].answer?.text, "Moved to Friday.")
    }

    func testNothingFoundRunsTheModelWithoutAPlaceholderAnswer() async {
        let counter = CallCounter()
        let updates = await run(unmatched, facts: nil, hooks: hooks(counter: counter))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(updates.map(\.stage), [.refining, .final])
        XCTAssertNil(updates[0].answer)
        XCTAssertEqual(updates[1].tier, .generated)
    }

    func testModelFindingNothingGivesAnHonestNotFoundWithSuggestions() async {
        let counter = CallCounter()
        let reply = VidurAnswer(text: "This wasn't discussed in the meeting.", kind: .notFound)
        let updates = await run(unmatched, facts: nil, hooks: hooks(counter: counter, reply: reply))
        let answer = updates.last?.answer
        XCTAssertEqual(answer?.kind, .notFound)
        XCTAssertTrue(answer?.text.contains("couldn\u{2019}t find anything about") == true)
        XCTAssertFalse(answer?.suggestions.isEmpty ?? true)
        XCTAssertTrue(answer?.isRecordable ?? false)
    }

    func testRefinementFailureKeepsTheQuickAnswerAndSaysSo() async {
        let counter = CallCounter()
        let updates = await run(reasoning, facts: nil, hooks: hooks(counter: counter, fail: true))
        let final = updates.last
        XCTAssertEqual(final?.stage, .final)
        XCTAssertEqual(final?.tier, .quote)
        XCTAssertEqual(final?.answer?.kind, .extractive)
        XCTAssertTrue(final?.answer?.notice?.contains("Quick answer shown") == true)
        XCTAssertTrue(final?.answer?.notice?.contains("model busy") == true)
    }

    func testSlowGenerationTimesOutAndKeepsTheQuickAnswer() async {
        let counter = CallCounter()
        let started = Date()
        let updates = await run(reasoning, facts: nil, hooks: hooks(counter: counter, delay: 5, timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "The deadline returns control promptly")
        let final = updates.last
        XCTAssertEqual(final?.tier, .quote)
        XCTAssertEqual(final?.answer?.kind, .extractive)
        XCTAssertTrue(final?.answer?.notice?.contains("too long") == true)
    }

    func testFailureWithNothingFoundStaysAnHonestNotFound() async {
        let counter = CallCounter()
        let updates = await run(unmatched, facts: nil, hooks: hooks(counter: counter, fail: true))
        XCTAssertEqual(updates.last?.answer?.kind, .notFound)
        XCTAssertTrue(updates.last?.answer?.notice?.contains("model busy") == true)
    }

    func testNoRefinementWhileMinutesAreProcessing() async {
        let counter = CallCounter()
        let updates = await run(unmatched, facts: nil, allow: false, hooks: hooks(counter: counter))
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates[0].answer?.notice?.contains("still being generated") == true)
        let quick = await run("When does the pricing page launch?", facts: nil, allow: false, hooks: hooks(counter: counter))
        XCTAssertEqual(quick.count, 1)
        XCTAssertEqual(quick[0].tier, .quote)
    }

    func testUserDisabledDeepAnswersSkipsTheModelAndExplains() async {
        let counter = CallCounter()
        let none = await run(unmatched, facts: nil, userDisabled: true, hooks: hooks(counter: counter))
        XCTAssertEqual(none.count, 1)
        XCTAssertTrue(none.last?.answer?.notice?.contains("Deep answers") == true)
        XCTAssertEqual(counter.count, 0)
    }

    func testMissingModelIsReportedAsNotFoundWithAHint() async {
        let counter = CallCounter()
        let updates = await run(unmatched, facts: nil, hooks: hooks(counter: counter, available: false))
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].answer?.kind, .notFound)
        XCTAssertTrue(updates[0].answer?.notice?.contains("not downloaded") == true)
    }

    func testFollowUpHistoryAndEveryMeetingsMinutesReachTheDeepTier() async {
        let counter = CallCounter()
        let inputs = InputBox()
        let earlier = VidurMeetingFacts(meetingID: UUID(), title: "Kickoff", date: Date(timeIntervalSince1970: 0))
        let history = [VidurChatTurn(question: "What did Rahul say about pricing?", answer: "Friday."),
                       VidurChatTurn(question: "And the vendor?", answer: "Pune.")]
        _ = await run("aur Neha ne?", facts: nil, additional: [earlier, facts], history: history,
                      hooks: hooks(counter: counter, inputs: inputs))
        XCTAssertEqual(inputs.inputs.count, 1)
        XCTAssertEqual(inputs.inputs[0].history, history)
        XCTAssertEqual(inputs.inputs[0].facts.map(\.title), ["Kickoff", "Weekly sync"])
        XCTAssertEqual(inputs.inputs[0].question, "aur Neha ne?")
    }

    func testFollowUpResolvesAgainstThePreviousQuestionWithoutTheModel() async {
        let counter = CallCounter()
        let tasks = [VidurTaskFact(title: "Send revised quote", owner: "Rahul", timestamp: 30),
                     VidurTaskFact(title: "Book the review room", owner: "Asha", timestamp: 5)]
        let withTasks = VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(), attendees: ["Rahul", "Asha"],
                                          attendanceRecorded: true, tasks: tasks)
        let history = [VidurChatTurn(question: "What tasks does Rahul have?", answer: "Send revised quote.")]
        let updates = await run("and Asha?", facts: withTasks, history: history, hooks: hooks(counter: counter))
        XCTAssertEqual(counter.count, 0)
        XCTAssertTrue(updates.last?.answer?.text.contains("Book the review room") == true)
        XCTAssertFalse(updates.last?.answer?.text.contains("Send revised quote") == true)
        XCTAssertEqual(updates.last?.answer?.people, ["Asha"])
        XCTAssertEqual(updates.last?.answer?.relatedTasks.map(\.title), ["Book the review room"])
    }

    func testEmptyAndOversizedQuestionsFailFast() async {
        let counter = CallCounter()
        let empty = await run("   ", facts: nil, hooks: hooks(counter: counter))
        XCTAssertEqual(empty.first?.answer?.kind, .failed)
        let long = await run(String(repeating: "q", count: 301), facts: nil, hooks: hooks(counter: counter))
        XCTAssertEqual(long.first?.answer?.kind, .failed)
        XCTAssertEqual(counter.count, 0)
    }

    func testStreamEndsAfterFinalUpdate() async {
        let counter = CallCounter()
        let request = VidurTieredRequest(question: "Who attended?", sources: sources,
                                         facts: VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(),
                                                                  attendees: ["Asha"], attendanceRecorded: true),
                                         length: .brief)
        var received: [VidurAnswerUpdate] = []
        for await update in VidurTieredAnswerService.stream(request, hooks: hooks(counter: counter)) { received.append(update) }
        XCTAssertEqual(received.map(\.stage), [.final])
    }

    private func naturalHooks(counter: CallCounter, warm: Bool = true, reply: String? = "Meera was away. Rahul and Asha were there.") -> VidurTieredHooks {
        VidurTieredHooks(
            refinementAvailable: { true },
            rephraseAvailable: { warm },
            rephrase: { _ in
                counter.increment()
                return reply
            },
            refine: { _ in
                counter.increment()
                return VidurAnswer(text: "Written by the model.", kind: .generated)
            })
    }

    func testFactualAnswerIsSaidNaturallyWhenTheModelIsWarm() async {
        let counter = CallCounter()
        let updates = await run("Who attended?", facts: populatedFacts, hooks: naturalHooks(counter: counter))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(updates.map(\.stage), [.refining, .final])
        XCTAssertTrue(updates[0].answer?.text.contains("Present (2)") == true, "The saved wording shows first")
        XCTAssertEqual(updates[1].tier, .generated)
        XCTAssertEqual(updates[1].answer?.text, "Meera was away. Rahul and Asha were there.")
        XCTAssertEqual(updates[1].answer?.kind, .generated)
    }

    func testSavedWordingIsKeptWhenTheRewriteIsRejected() async {
        let counter = CallCounter()
        let updates = await run("Who attended?", facts: populatedFacts, hooks: naturalHooks(counter: counter, reply: nil))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(updates.map(\.stage), [.refining, .final])
        XCTAssertEqual(updates[1].tier, .structured)
        XCTAssertTrue(updates[1].answer?.text.contains("Present (2)") == true)
    }

    func testNoRewriteWhenTheModelIsNotWarm() async {
        let counter = CallCounter()
        let updates = await run("Who attended?", facts: populatedFacts, hooks: naturalHooks(counter: counter, warm: false))
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(updates.map(\.stage), [.final])
        XCTAssertEqual(updates[0].tier, .structured)
    }

    func testNoRewriteWhenDeepAnswersAreOff() async {
        let counter = CallCounter()
        let updates = await run("Who attended?", facts: populatedFacts, userDisabled: true, hooks: naturalHooks(counter: counter))
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(updates.map(\.stage), [.final])
    }

    func testOpenEndedQuestionGoesToTheModelEvenWhenTheMinutesHaveSomething() async {
        let counter = CallCounter()
        let updates = await run("What were the main concerns about the pricing page?", facts: populatedFacts,
                                hooks: naturalHooks(counter: counter))
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(updates.map(\.stage), [.refining, .final])
        XCTAssertNil(updates[0].answer, "An open question shows the search animation, not a loose quote")
        XCTAssertEqual(updates[1].answer?.text, "Written by the model.")
        XCTAssertEqual(updates[1].tier, .generated)
    }
    func testRecordAdapterMergesMinutesAndTranscript() {
        let decision = VidurFactLine(text: "Launch Friday", timestamp: 12, quote: "launch moves to Friday", speaker: "Asha")
        let task = VidurTaskFact(title: "Send quote", owner: "Rahul", timestamp: 30)
        let rich = VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(), attendees: ["Asha"],
                                     decisions: [decision], tasks: [task])
        let extra = VidurSourceMeeting(id: UUID(), title: "Standup", date: Date(), turns: [
            VidurSourceTurn(text: "Hello", start: 1, end: 2, speaker: nil)])
        let records = VidurRecordAdapter.records(facts: [rich], sources: sources + [extra])
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].turns.count, 2)
        XCTAssertEqual(records[0].decisions.first?.text, "Launch Friday")
        XCTAssertEqual(records[0].tasks.first?.owner, "Rahul")
        XCTAssertEqual(records[1].title, "Standup")
    }
}
final class VidurHindiRoutingTests: XCTestCase {
    func testFollowUpKeepsThePreviousQuestionsLanguage() {
        let history = [VidurChatTurn(question: "Pricing ke baare mein kya tay hua?", answer: "Friday.")]
        XCTAssertEqual(VidurTieredAnswerService.answerLanguage(question: "And Neha?", history: history), .hinglish)
        XCTAssertEqual(VidurTieredAnswerService.answerLanguage(question: "And Neha?", history: []), .english)
        XCTAssertEqual(VidurTieredAnswerService.answerLanguage(
            question: "What did Neha say about the vendor contract renewal?", history: history), .english)
    }

    func testHindiQuestionGetsHindiNotFoundWhenNothingMatches() async {
        let language = VidurAnswerLanguage.detect("\u{092C}\u{091C}\u{091F} \u{0915}\u{094D}\u{092F}\u{093E} \u{0925}\u{093E}?")
        XCTAssertEqual(language, .hindi)
        XCTAssertEqual(VidurGroundedPrompt.notDiscussed(for: language), "\u{092E}\u{0940}\u{091F}\u{093F}\u{0902}\u{0917} \u{092E}\u{0947}\u{0902} \u{0907}\u{0938} \u{092A}\u{0930} \u{092C}\u{093E}\u{0924} \u{0928}\u{0939}\u{0940}\u{0902} \u{0939}\u{0941}\u{0908}\u{0964}")
    }
}
