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

final class VidurIntentRoutingTests: XCTestCase {
    private let names = ["Rahul Sharma", "Asha", "Meera"]

    private func route(_ question: String) -> VidurRoute {
        VidurIntentRouter.route(question: question, participantNames: names)
    }

    func testTaskQuestions() {
        XCTAssertEqual(route("Which actions did we agree on?").intents, [.tasks])
        XCTAssertEqual(route("Who owns the vendor follow up?").intents, [.tasks])
        XCTAssertEqual(route("What are the deadlines?").intents, [.tasks])
        XCTAssertEqual(route("What are the deadlines?").taskFilter, .due)
    }

    func testDecisionsAndOpenIssues() {
        XCTAssertEqual(route("What did we decide?").intents, [.decisions])
        XCTAssertEqual(route("What is still unresolved?").intents, [.openIssues])
        XCTAssertEqual(route("Any open questions left?").intents, [.openIssues])
    }

    func testAttendeesAbsenteesAndBoth() {
        XCTAssertEqual(route("Who attended?").intents, [.attendees])
        XCTAssertEqual(route("Who was absent?").intents, [.absent])
        XCTAssertEqual(route("Who is not present?").intents, [.absent])
        XCTAssertEqual(Set(route("Who attended and who was absent?").intents), [.attendees, .absent])
    }

    func testAgendaSummaryDurationDate() {
        XCTAssertEqual(route("What was on the agenda?").intents, [.agenda])
        XCTAssertEqual(route("Give me a summary").intents, [.summary])
        XCTAssertEqual(route("How long was the meeting?").intents, [.duration])
        XCTAssertEqual(route("When was the meeting?").intents, [.date])
    }

    func testPersonSpecificTaskQuestion() {
        let result = route("What did Rahul agree to?")
        XCTAssertEqual(result.intents, [.tasks])
        XCTAssertEqual(result.people, ["Rahul Sharma"])
        XCTAssertTrue(result.residual.isEmpty)
    }

    func testPossessiveNameIsMatched() {
        let result = route("What are Asha's tasks?")
        XCTAssertEqual(result.people, ["Asha"])
        XCTAssertEqual(result.intents, [.tasks])
    }

    func testHinglishQuestions() {
        XCTAssertEqual(route("Rahul ka kaam kya hai?").intents, [.tasks])
        XCTAssertEqual(route("Rahul ka kaam kya hai?").people, ["Rahul Sharma"])
        XCTAssertEqual(route("Kya tay hua?").intents, [.decisions])
        XCTAssertEqual(route("Kab tak deadline hai?").taskFilter, .due)
        XCTAssertEqual(route("Kaun kaun aaya tha?").intents, [.attendees])
    }

    func testTaskFilters() {
        XCTAssertEqual(route("Show open tasks").taskFilter, .open)
        XCTAssertEqual(route("Which tasks are not completed?").taskFilter, .open)
        XCTAssertEqual(route("Which tasks are done?").taskFilter, .done)
        XCTAssertEqual(route("Any overdue tasks?").taskFilter, .overdue)
    }

    func testTopicWordsStayResidualSoTheyAreNotAnsweredFromTheSummary() {
        let result = route("What did we discuss about pricing?")
        XCTAssertEqual(result.intents, [.summary])
        XCTAssertEqual(result.residual, ["pricing"])
    }

    func testPlainTopicQuestionHasNoIntent() {
        XCTAssertTrue(route("Why did the vendor delay shipment?").intents.isEmpty)
    }
}

final class VidurStructuredAnswererTests: XCTestCase {
    private let meetingID = UUID()

    private func facts(tasks: [VidurTaskFact] = [], decisions: [VidurFactLine] = [], issues: [VidurFactLine] = [],
                       attendees: [String] = ["Rahul Sharma", "Asha"], absent: [String] = ["Meera"],
                       attendanceRecorded: Bool = true) -> VidurMeetingFacts {
        VidurMeetingFacts(meetingID: meetingID, title: "Weekly sync", date: Date(timeIntervalSince1970: 1_767_225_600),
                          duration: 1_390, attendees: attendees, absent: absent, attendanceRecorded: attendanceRecorded,
                          agenda: ["Pricing page", "Vendor payments"], summary: "Pricing launch moved to Friday.",
                          discussion: ["Legal review is pending"], decisions: decisions, openIssues: issues, tasks: tasks)
    }

    private var sampleTasks: [VidurTaskFact] {
        [
            VidurTaskFact(title: "Send revised quote", owner: "Rahul Sharma", dueDate: Date(timeIntervalSince1970: 1_767_300_000),
                          timestamp: 125, quote: "Rahul will send the revised quote"),
            VidurTaskFact(title: "Book the pricing review room", owner: "Asha", isCompleted: true, timestamp: 40,
                          quote: "Asha books the room"),
            VidurTaskFact(title: "Update vendor payment tracker", owner: "Rahul Sharma", timestamp: 200,
                          quote: "tracker update is on Rahul"),
            VidurTaskFact(title: "Check legal wording", owner: nil, dueText: "kal tak", isSuggestion: true)
        ]
    }

    func testPersonSpecificTasksOnlyListThatPersonsTasks() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "What did Rahul agree to?", facts: facts(tasks: sampleTasks)))
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.answer.text.contains("Send revised quote"))
        XCTAssertTrue(result.answer.text.contains("Update vendor payment tracker"))
        XCTAssertFalse(result.answer.text.contains("Book the pricing review room"))
        XCTAssertEqual(result.answer.citations.first?.timecode, "02:05")
        XCTAssertEqual(result.answer.citations.first?.meetingID, meetingID)
    }

    func testOpenTasksExcludeCompletedAndMarkSuggestions() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "Show open tasks", facts: facts(tasks: sampleTasks)))
        XCTAssertFalse(result.answer.text.contains("Book the pricing review room"))
        XCTAssertTrue(result.answer.text.contains("suggested, not confirmed yet"))
        XCTAssertTrue(result.answer.text.contains("no owner set"))
        XCTAssertTrue(result.answer.text.hasPrefix("3 open tasks"))
    }

    func testTopicFilterKeepsOnlyMatchingTasks() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "Which actions are open for vendor?", facts: facts(tasks: sampleTasks)))
        XCTAssertTrue(result.answer.text.contains("Update vendor payment tracker"))
        XCTAssertFalse(result.answer.text.contains("Send revised quote"))
    }

    func testTopicWithNoMatchingRowsFallsThroughInsteadOfClaimingAnAnswer() {
        XCTAssertNil(VidurStructuredAnswerer.answer(question: "Which actions are open for hiring?", facts: facts(tasks: sampleTasks)))
    }

    func testDecisionsAreListedWithTimestamps() throws {
        let decisions = [VidurFactLine(text: "Launch pricing page on Friday", timestamp: 61, quote: "we launch on Friday", speaker: "Asha")]
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "What did we decide?", facts: facts(decisions: decisions)))
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.answer.text.contains("Launch pricing page on Friday"))
        XCTAssertEqual(result.answer.citations.first?.timecode, "01:01")
        XCTAssertEqual(result.answer.citations.first?.speaker, "Asha")
    }

    func testMissingDecisionsAreIncompleteSoTranscriptSearchStillRuns() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "What did we decide?", facts: facts()))
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.answer.text.contains("No decisions are saved"))
    }

    func testAttendeesAndAbsent() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "Who attended and who was absent?", facts: facts()))
        XCTAssertTrue(result.answer.text.contains("Present (2): Rahul Sharma, Asha"))
        XCTAssertTrue(result.answer.text.contains("Absent"))
        XCTAssertTrue(result.answer.text.contains("Meera"))
    }

    func testUnconfirmedAttendanceIsNotReportedAsNobodyAbsent() throws {
        let result = try XCTUnwrap(VidurStructuredAnswerer.answer(
            question: "Who was absent?", facts: facts(absent: [], attendanceRecorded: false)))
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.answer.text.contains("not been confirmed"))
    }

    func testAgendaAndDuration() throws {
        let agenda = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "What was the agenda?", facts: facts()))
        XCTAssertTrue(agenda.answer.text.contains("Pricing page"))
        let duration = try XCTUnwrap(VidurStructuredAnswerer.answer(question: "How long was it?", facts: facts()))
        XCTAssertTrue(duration.answer.text.contains("23 min 10 s"))
    }

    func testSummaryWithTopicIsNotAnsweredFromGenericSummary() {
        XCTAssertNil(VidurStructuredAnswerer.answer(question: "What did we discuss about hiring?", facts: facts()))
    }

    func testQuestionWithoutIntentReturnsNil() {
        XCTAssertNil(VidurStructuredAnswerer.answer(question: "Why did the vendor delay shipment?", facts: facts(tasks: sampleTasks)))
    }

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

final class VidurFastAnswererTests: XCTestCase {
    private let meeting = VidurSourceMeeting(id: UUID(), title: "Vendor sync", date: Date(), turns: [
        VidurSourceTurn(text: "Aaj ka agenda budget aur hiring hai", start: 3, end: 6, speaker: "Asha"),
        VidurSourceTurn(text: "Vendor payment agle hafte tak clear karna hai. Invoice bhi check karna.", start: 65, end: 72, speaker: "Rahul"),
        VidurSourceTurn(text: "Budget approval Meera dekhegi", start: 90, end: 95, speaker: "Asha")
    ])

    func testHinglishQuestionFindsTheRightTurnWithTimestamp() throws {
        let answer = try XCTUnwrap(VidurFastAnswerer.answer(question: "Vendor payment kab tak clear hoga?", sources: [meeting]))
        XCTAssertEqual(answer.kind, .extractive)
        XCTAssertEqual(answer.citations.first?.timecode, "01:05")
        XCTAssertEqual(answer.citations.first?.speaker, "Rahul")
        XCTAssertTrue(answer.text.contains("[01:05]"))
    }

    func testCitationsAreExactSubstringsOfTheTurn() throws {
        let answer = try XCTUnwrap(VidurFastAnswerer.answer(question: "vendor payment invoice", sources: [meeting]))
        for citation in answer.citations {
            XCTAssertTrue(meeting.turns.contains { $0.text.contains(citation.quote) })
        }
    }

    func testWeakOverlapReturnsNil() {
        XCTAssertNil(VidurFastAnswerer.answer(question: "Which cloud provider hosts the database backups", sources: [meeting]))
    }

    func testSpeakerFilterRestrictsToThatPerson() throws {
        let sources = [meeting]
        let speakers = VidurFastAnswerer.speakerFilter(question: "What did Asha say about budget?", sources: sources)
        XCTAssertEqual(speakers, ["Asha"])
        let answer = try XCTUnwrap(VidurFastAnswerer.answer(question: "What did Asha say about budget?", sources: sources, speakerFilter: speakers))
        XCTAssertTrue(answer.citations.allSatisfy { $0.speaker == "Asha" })
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
    func testDevanagariQuestionsRouteToTheSameIntentsAsEnglish() {
        let names = ["Rahul", "Asha"]
        XCTAssertEqual(VidurIntentRouter.route(question: "\u{0915}\u{094D}\u{092F}\u{093E} \u{0924}\u{092F} \u{0939}\u{0941}\u{0906}?", participantNames: names).intents, [.decisions])
        XCTAssertEqual(VidurIntentRouter.route(question: "\u{092B}\u{0948}\u{0938}\u{0932}\u{0947} \u{0915}\u{094D}\u{092F}\u{093E} \u{0925}\u{0947}?", participantNames: names).intents, [.decisions])
        XCTAssertEqual(VidurIntentRouter.route(question: "Rahul \u{0915}\u{093E} \u{0915}\u{093E}\u{092E} \u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0948}?", participantNames: names).intents, [.tasks])
        XCTAssertEqual(VidurIntentRouter.route(question: "\u{0905}\u{0928}\u{0941}\u{092A}\u{0938}\u{094D}\u{0925}\u{093F}\u{0924} \u{0915}\u{094C}\u{0928} \u{0925}\u{093E}?", participantNames: names).intents, [.absent])
    }

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
