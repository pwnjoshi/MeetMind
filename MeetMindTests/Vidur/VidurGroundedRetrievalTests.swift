import XCTest
import Foundation
import OfflineEngineKit
@testable import MeetMind

private enum Fixture {
    static let meetingID = UUID()
    static let pawanDevanagari = "\u{092A}\u{0935}\u{0928}"
    static let rahulDevanagari = "\u{0930}\u{093E}\u{0939}\u{0941}\u{0932}"

    static var facts: VidurMeetingFacts {
        VidurMeetingFacts(
            meetingID: meetingID, title: "Weekly sync", date: Date(timeIntervalSince1970: 1_767_225_600), duration: 1_390,
            attendees: ["Rahul", "Neha"], absent: ["Pawan"], attendanceRecorded: true,
            agenda: ["Pricing page", "Vendor payments"], summary: "Pricing launch moved to Friday because legal review is pending.",
            discussion: ["Legal review is pending for the pricing page"],
            decisions: [VidurFactLine(text: "Launch the pricing page on Friday", timestamp: 61,
                                      quote: "we launch on Friday", speaker: "Asha")],
            openIssues: [VidurFactLine(text: "Vendor contract wording is unresolved", timestamp: 90, quote: nil, speaker: nil)],
            tasks: [
                VidurTaskFact(title: "Send revised quote", owner: "Rahul", dueDate: Date(timeIntervalSince1970: 1_767_300_000),
                              timestamp: 125, quote: "Rahul will send the revised quote"),
                VidurTaskFact(title: "Review vendor contract", owner: "Neha", dueText: "kal tak", timestamp: 150,
                              quote: "Neha reviews the contract"),
                VidurTaskFact(title: "Book the pricing review room", owner: "Asha", isCompleted: true),
                VidurTaskFact(title: "Check legal wording", owner: nil, dueText: "Monday", isSuggestion: true)
            ])
    }

    static var source: VidurSourceMeeting {
        VidurSourceMeeting(id: meetingID, title: "Weekly sync", date: Date(timeIntervalSince1970: 1_767_225_600), turns: [
            VidurSourceTurn(text: "Pricing page launch moves to Friday because legal review is pending", start: 12, end: 18, speaker: "Asha"),
            VidurSourceTurn(text: "Rahul will send the revised quote tomorrow", start: 65, end: 70, speaker: "S1"),
            VidurSourceTurn(text: "\(pawanDevanagari) \u{0915}\u{0932} \u{0924}\u{0915} \u{0915}\u{094B}\u{091F}\u{0947}\u{0936}\u{0928} \u{092D}\u{0947}\u{091C}\u{0947}\u{0917}\u{093E}",
                            start: 80, end: 85, speaker: "Neha"),
            VidurSourceTurn(text: "Budget approval Meera dekhegi", start: 90, end: 95, speaker: "Asha"),
            VidurSourceTurn(text: "Check the pricing sheet again", start: 100, end: 100, speaker: "Note")
        ])
    }

    static var corpus: [VidurContextSnippet] { VidurSnippetBuilder.corpus(sources: [source], facts: [facts]) }
}

final class VidurSnippetBuilderTests: XCTestCase {
    func testMinutesTranscriptAndNotesAllBecomeSnippets() {
        let kinds = Set(Fixture.corpus.map(\.kind))
        for kind in [VidurContextSnippet.Kind.summary, .agenda, .attendance, .decision, .action, .openIssue, .discussion, .transcript, .note] {
            XCTAssertTrue(kinds.contains(kind), "missing \(kind)")
        }
        XCTAssertEqual(Fixture.corpus.filter { $0.kind == .action }.count, 4)
        XCTAssertEqual(Fixture.corpus.filter { $0.kind == .transcript }.count, 4)
    }

    func testSummaryIsFirstPinnedAndCarriesTitleDateAndDuration() throws {
        let summary = try XCTUnwrap(Fixture.corpus.first)
        XCTAssertEqual(summary.kind, .summary)
        XCTAssertTrue(summary.isPinned)
        XCTAssertTrue(summary.text.contains("Weekly sync"))
        XCTAssertTrue(summary.text.contains("23 min"))
        XCTAssertTrue(summary.text.contains("legal review is pending"))
    }

    func testActionSnippetsStateOwnerDueStatusAndAcceptance() throws {
        let actions = Fixture.corpus.filter { $0.kind == .action }.map(\.text)
        let send = try XCTUnwrap(actions.first { $0.contains("Send revised quote") })
        XCTAssertTrue(send.contains("owner: Rahul"))
        XCTAssertTrue(send.contains("due: "))
        XCTAssertTrue(send.contains("status: open"))
        XCTAssertTrue(send.contains("accepted"))
        XCTAssertFalse(send.contains("not yet accepted"))
        let review = try XCTUnwrap(actions.first { $0.contains("Review vendor contract") })
        XCTAssertTrue(review.contains("due: kal tak"))
        let done = try XCTUnwrap(actions.first { $0.contains("Book the pricing review room") })
        XCTAssertTrue(done.contains("status: done"))
        XCTAssertTrue(done.contains("due: not set"))
        let suggested = try XCTUnwrap(actions.first { $0.contains("Check legal wording") })
        XCTAssertTrue(suggested.contains("owner: not set"))
        XCTAssertTrue(suggested.contains("suggested by Vidur, not yet accepted"))
    }

    func testDecisionIncludesWhoStatedItAndTheMoment() throws {
        let decision = try XCTUnwrap(Fixture.corpus.first { $0.kind == .decision })
        XCTAssertTrue(decision.text.contains("decided by Asha"))
        XCTAssertTrue(decision.text.contains("[01:01]"))
        XCTAssertEqual(decision.timestamp, 61)
    }

    func testAttendanceListsPresentAndAbsent() throws {
        let attendance = try XCTUnwrap(Fixture.corpus.first { $0.kind == .attendance })
        XCTAssertTrue(attendance.text.contains("present: Rahul, Neha"))
        XCTAssertTrue(attendance.text.contains("Absent: Pawan"))
    }

    func testTranscriptSnippetsUseSpeakerNamesAndTimecodesNeverRawLabels() {
        let transcript = Fixture.corpus.filter { $0.kind == .transcript }.map(\.text)
        XCTAssertTrue(transcript.contains { $0.hasPrefix("Asha [00:12]: Pricing page launch") })
        XCTAssertTrue(transcript.contains { $0.hasPrefix("Speaker 1 [01:05]: Rahul will send") })
        XCTAssertFalse(transcript.contains { $0.hasPrefix("S1 ") })
        XCTAssertTrue(Fixture.corpus.contains { $0.kind == .note && $0.text.hasPrefix("Note [01:40]: Check the pricing sheet") })
    }

    func testDisplayNames() {
        XCTAssertEqual(VidurSnippetBuilder.displayName("S1"), "Speaker 1")
        XCTAssertEqual(VidurSnippetBuilder.displayName("speaker 12"), "Speaker 12")
        XCTAssertEqual(VidurSnippetBuilder.displayName("Sandeep"), "Sandeep")
        XCTAssertEqual(VidurSnippetBuilder.displayName(nil), "Unknown speaker")
        XCTAssertEqual(VidurSnippetBuilder.displayName("  "), "Unknown speaker")
    }

    func testSeveralMeetingsTagEverySnippetWithItsMeeting() {
        let other = VidurSourceMeeting(id: UUID(), title: "Kickoff", date: Date(timeIntervalSince1970: 0), turns: [
            VidurSourceTurn(text: "We start on Monday", start: 3, end: 4, speaker: "Asha")
        ])
        let corpus = VidurSnippetBuilder.corpus(sources: [other, Fixture.source], facts: [Fixture.facts])
        XCTAssertTrue(corpus.allSatisfy { $0.text.hasPrefix("[") })
        XCTAssertTrue(corpus.contains { $0.text.hasPrefix("[Kickoff,") && $0.meetingTitle == "Kickoff" })
    }
}

final class VidurTransliterationTests: XCTestCase {
    func testRomanAndDevanagariNamesShareASkeleton() {
        XCTAssertEqual(VidurTransliteration.skeleton("Pawan"), "pvn")
        XCTAssertEqual(VidurTransliteration.skeleton("\u{092A}\u{0935}\u{0928}"), "pvn")
        XCTAssertEqual(VidurTransliteration.skeleton("Rahul"), VidurTransliteration.skeleton("\u{0930}\u{093E}\u{0939}\u{0941}\u{0932}"))
        XCTAssertEqual(VidurTransliteration.skeleton("Neha"), VidurTransliteration.skeleton("\u{0928}\u{0947}\u{0939}\u{093E}"))
        XCTAssertEqual(VidurTransliteration.skeleton("Priya"), VidurTransliteration.skeleton("\u{092A}\u{094D}\u{0930}\u{093F}\u{092F}\u{093E}"))
        XCTAssertEqual(VidurTransliteration.skeleton("Sandeep"), VidurTransliteration.skeleton("\u{0938}\u{0902}\u{0926}\u{0940}\u{092A}"))
        XCTAssertEqual(VidurTransliteration.skeleton("Chandra"), VidurTransliteration.skeleton("\u{091A}\u{0902}\u{0926}\u{094D}\u{0930}"))
        XCTAssertEqual(VidurTransliteration.skeleton("Vikram"), VidurTransliteration.skeleton("\u{0935}\u{093F}\u{0915}\u{094D}\u{0930}\u{092E}"))
    }

    func testDifferentNamesDoNotCollide() {
        XCTAssertNotEqual(VidurTransliteration.skeleton("Pawan"), VidurTransliteration.skeleton("Rahul"))
        XCTAssertNotEqual(VidurTransliteration.skeleton("Pawan"), VidurTransliteration.skeleton("\u{0930}\u{093E}\u{0939}\u{0941}\u{0932}"))
    }
}

final class VidurGroundedRetrieverTests: XCTestCase {
    private let names = ["Rahul", "Neha", "Pawan", "Asha"]

    private func texts(_ question: String, history: [VidurChatTurn] = []) -> [VidurContextSnippet] {
        VidurGroundedRetriever.select(question: question, history: history, corpus: Fixture.corpus, names: names)
    }

    func testMinutesSummaryIsAlwaysFirstAndPinned() throws {
        for question in ["Budget approval kaun dekhega?", "Anything about the weather?", "\u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0941}\u{0906}?"] {
            let selected = texts(question)
            XCTAssertEqual(selected.first?.kind, .summary, question)
            XCTAssertEqual(selected.first?.isPinned, true, question)
        }
    }

    func testRomanNameFindsTheDevanagariTranscriptTurn() {
        let selected = texts("Pawan ko kya karna hai?")
        let turn = selected.first { $0.kind == .transcript && $0.text.contains(Fixture.pawanDevanagari) }
        XCTAssertNotNil(turn, "Devanagari turn must be retrieved for the Roman spelling")
        let position = selected.firstIndex { $0.text.contains(Fixture.pawanDevanagari) } ?? 99
        XCTAssertLessThan(position, 4)
    }

    func testDevanagariNameFindsRomanTranscriptAndMinutes() {
        let question = "\(Fixture.rahulDevanagari) \u{0915}\u{093E} \u{0915}\u{093E}\u{092E} \u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0948}?"
        let selected = texts(question)
        let action = selected.first { $0.kind == .action && $0.text.contains("Send revised quote") }
        XCTAssertNotNil(action, "Rahul's action must be found from the Devanagari spelling")
        XCTAssertTrue(selected.contains { $0.kind == .transcript && $0.text.contains("Rahul will send the revised quote") })
        let other = selected.first { $0.kind == .action && $0.text.contains("Review vendor contract") }
        if let other, let action {
            let order = selected.map(\.text)
            XCTAssertLessThan(order.firstIndex(of: action.text) ?? 99, order.firstIndex(of: other.text) ?? 99)
        }
    }

    func testMinutesItemsNamingAPersonInTheQuestionArePinned() throws {
        let selected = texts("Neha ka kya kaam hai?")
        let neha = try XCTUnwrap(selected.first { $0.kind == .action && $0.text.contains("Review vendor contract") })
        XCTAssertTrue(neha.isPinned)
        let rahul = try XCTUnwrap(selected.first { $0.kind == .action && $0.text.contains("Send revised quote") })
        XCTAssertFalse(rahul.isPinned)
    }

    func testSynonymsConnectHindiAndHinglishWordsToMinutesKinds() {
        func firstOfKind(_ kind: VidurContextSnippet.Kind, for question: String) -> Int? {
            texts(question).firstIndex { $0.kind == kind }
        }
        // "faisla" and the Devanagari word both mean decision, so the decision item ranks near the top.
        let hinglish = firstOfKind(.decision, for: "pricing ka faisla kya hua?")
        XCTAssertNotNil(hinglish)
        XCTAssertLessThan(hinglish ?? 99, 4)
        XCTAssertNotNil(firstOfKind(.decision, for: "\u{092B}\u{0948}\u{0938}\u{0932}\u{093E} \u{0915}\u{094D}\u{092F}\u{093E} \u{0939}\u{0941}\u{0906}?"))
        // "kaam" means task/action.
        XCTAssertNotNil(firstOfKind(.action, for: "vendor ka kaam kisko mila?"))
        // "kab tak" means deadline, which lives on action items.
        XCTAssertNotNil(firstOfKind(.action, for: "quote kab tak bhejna hai?"))
    }

    func testDecisionQuestionPutsDecisionAheadOfUnrelatedTranscript() throws {
        let selected = texts("What did we decide?")
        let decision = try XCTUnwrap(selected.firstIndex { $0.kind == .decision })
        let budget = selected.firstIndex { $0.text.contains("Budget approval") }
        XCTAssertLessThan(decision, budget ?? Int.max)
    }

    func testFollowUpBorrowsThePreviousQuestionsTopic() throws {
        let history = [VidurChatTurn(question: "What did Rahul say about the revised quote?", answer: "He will send it tomorrow.")]
        XCTAssertEqual(VidurGroundedRetriever.retrievalQuery(question: "aur Neha ne?", history: history),
                       history[0].question + " aur Neha ne?")
        XCTAssertEqual(VidurGroundedRetriever.retrievalQuery(question: "What did Neha say about the vendor contract?", history: history),
                       "What did Neha say about the vendor contract?")
        let selected = texts("aur Neha ne?", history: history)
        XCTAssertTrue(selected.contains { $0.text.contains("revised quote") })
        XCTAssertTrue(selected.contains { $0.text.contains("Neha") })
    }

    func testSelectionIsBoundedAndHasNoDuplicates() {
        let turns = (0..<200).map { VidurSourceTurn(text: "pricing discussion number \($0)", start: Double($0), end: Double($0 + 1), speaker: "Asha") }
        let source = VidurSourceMeeting(id: Fixture.meetingID, title: "Long", date: Date(), turns: turns)
        let corpus = VidurSnippetBuilder.corpus(sources: [source], facts: [Fixture.facts])
        let selected = VidurGroundedRetriever.select(question: "pricing", corpus: corpus, names: names)
        XCTAssertLessThanOrEqual(selected.count, VidurGroundedRetriever.defaultLimit)
        XCTAssertEqual(Set(selected.map(\.text)).count, selected.count)
    }

    func testEmptyCorpusSelectsNothing() {
        XCTAssertTrue(VidurGroundedRetriever.select(question: "anything", corpus: []).isEmpty)
    }

    func testNeighbouringTurnsOfTopTranscriptHitsAreIncluded() {
        let selected = texts("Pricing page launch Friday legal review")
        let lines = selected.map(\.text)
        XCTAssertTrue(lines.contains { $0.contains("Rahul will send the revised quote") }, "next turn gives context")
    }
}

final class VidurGroundedAnswerBuilderTests: XCTestCase {
    private var snippets: [VidurContextSnippet] { VidurGroundedRetriever.select(question: "Launch pricing page Friday", corpus: Fixture.corpus, names: ["Asha"]) }

    private func result(answer: String = "The pricing page launches on Friday.", found: Bool = true, cited: [Int], kept: [Int]? = nil) -> VidurGroundedResult {
        VidurGroundedResult(answer: answer, found: found, citedIndices: cited, keptIndices: kept ?? Array(snippets.indices),
                            language: .english, usedWarmSession: true, promptTokens: 900, truncated: false)
    }

    func testCitedMinutesAndTranscriptSnippetsBecomeSourceRows() throws {
        let all = snippets
        let decision = try XCTUnwrap(all.firstIndex { $0.kind == .decision })
        let turn = try XCTUnwrap(all.firstIndex { $0.kind == .transcript && $0.text.contains("Pricing page launch moves") })
        let answer = try VidurGroundedAnswerBuilder.build(result: result(cited: [decision, turn]), snippets: all, question: "Launch pricing page Friday")
        XCTAssertEqual(answer.kind, .generated)
        XCTAssertEqual(answer.citations.count, 2)
        let minutes = answer.citations[0]
        XCTAssertEqual(minutes.sourceLabel, "Decision")
        XCTAssertTrue(minutes.hasTimestamp)
        XCTAssertEqual(minutes.timecode, "01:01")
        let quote = answer.citations[1]
        XCTAssertNil(quote.sourceLabel)
        XCTAssertEqual(quote.timecode, "00:12")
        XCTAssertEqual(quote.speaker, "Asha")
        XCTAssertTrue(quote.quote.contains("Pricing page launch moves to Friday"))
        XCTAssertNil(answer.notice)
    }

    func testMinutesItemWithoutAMomentHasNoTimestamp() throws {
        let all = snippets
        let summary = try XCTUnwrap(all.firstIndex { $0.kind == .summary })
        let answer = try VidurGroundedAnswerBuilder.build(result: result(cited: [summary]), snippets: all, question: "pricing")
        XCTAssertEqual(answer.citations.first?.sourceLabel, "Summary")
        XCTAssertEqual(answer.citations.first?.hasTimestamp, false)
    }

    func testOutOfRangeAndDuplicateCitationsAreIgnored() throws {
        let all = snippets
        let answer = try VidurGroundedAnswerBuilder.build(result: result(cited: [0, 0, 999, -1]), snippets: all, question: "pricing")
        XCTAssertEqual(answer.citations.count, 1)
    }

    func testAtMostFourSourcesAreShown() throws {
        let all = snippets
        let answer = try VidurGroundedAnswerBuilder.build(result: result(cited: Array(all.indices)), snippets: all, question: "pricing")
        XCTAssertLessThanOrEqual(answer.citations.count, VidurGroundedAnswerBuilder.maximumCitations)
    }

    func testUncitedAnswerThatSharesWordsWithTheSnippetsGetsClosestSources() throws {
        let all = snippets
        let answer = try VidurGroundedAnswerBuilder.build(
            result: result(answer: "The pricing page launch moves to Friday.", cited: []), snippets: all, question: "pricing")
        XCTAssertFalse(answer.citations.isEmpty)
        XCTAssertTrue(answer.notice?.contains("closest matches") == true)
    }

    func testUncitedAnswerUnrelatedToTheSnippetsIsRejected() {
        XCTAssertThrowsError(try VidurGroundedAnswerBuilder.build(
            result: result(answer: "Quarterly revenue grew twelve percent.", cited: []), snippets: snippets, question: "pricing")) { error in
            XCTAssertEqual(error as? VidurGroundingError, .uncited)
        }
    }

    func testNotFoundKeepsTheLocalizedSentenceAndNoSources() throws {
        let hindi = VidurGroundedResult(answer: VidurGroundedPrompt.notDiscussedHindi, found: false, citedIndices: [], keptIndices: [0],
                                        language: .hindi, usedWarmSession: true, promptTokens: 500, truncated: false)
        let answer = try VidurGroundedAnswerBuilder.build(result: hindi, snippets: snippets, question: "q")
        XCTAssertEqual(answer.kind, .notFound)
        XCTAssertEqual(answer.text, VidurGroundedPrompt.notDiscussedHindi)
        XCTAssertTrue(answer.citations.isEmpty)
        XCTAssertTrue(answer.isRecordable)
    }
}

final class VidurDeadlineTests: XCTestCase {
    func testFastWorkReturnsItsValue() async throws {
        let value = try await VidurDeadline.run(seconds: 2) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testSlowWorkTimesOutAndIsCancelled() async {
        do {
            _ = try await VidurDeadline.run(seconds: 0.05) { () -> Int in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? VidurGroundingError, .timedOut)
        }
    }

    func testWorkErrorsPropagate() async {
        struct Boom: Error {}
        do {
            _ = try await VidurDeadline.run(seconds: 2) { () -> Int in throw Boom() }
            XCTFail("Expected an error")
        } catch { XCTAssertTrue(error is Boom) }
    }

    func testDeepAnswersAreOnByDefault() {
        let key = VidurDeepAnswerSetting.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(VidurDeepAnswerSetting.isEnabled)
        VidurDeepAnswerSetting.isEnabled = false
        XCTAssertFalse(VidurDeepAnswerSetting.isEnabled)
    }
}
