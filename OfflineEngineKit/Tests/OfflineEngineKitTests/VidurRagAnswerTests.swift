import XCTest
@testable import OfflineEngineKit

final class VidurRagAnswerTests: XCTestCase {
    // MARK: Streaming parser

    func testPartialAnswerGrowsAsTheJSONIsWritten() {
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: ""), "")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answ"), "")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\""), "")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\"You have 2 open ta"), "You have 2 open ta")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\": \"Pawan has it."), "Pawan has it.")
    }

    func testPartialAnswerStopsAtTheClosingQuoteAndDecodesEscapes() {
        let json = "{\"answer\":\"He said \\\"yes\\\".\\nThen left.\",\"citations\":[\"c1\"],\"found\":true}"
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: json), "He said \"yes\".\nThen left.")
    }

    func testPartialAnswerHandlesUnicodeEscapesAndHalfWrittenOnes() {
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\"\\u0935\\u0947 done"), "\u{0935}\u{0947} done")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\"ok \\u09"), "ok ")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\"ok \\"), "ok ")
        XCTAssertEqual(VidurRagAnswerParser.partialAnswer(from: "{\"answer\":\"caf\u{FFFD}"), "caf")
    }

    func testCleanRemovesBlockMarkersAndMarkdown() {
        XCTAssertEqual(VidurRagAnswerParser.clean("Maya owns it [2]."), "Maya owns it.")
        XCTAssertEqual(VidurRagAnswerParser.clean("Two reasons [1, 3] came up."), "Two reasons came up.")
        XCTAssertEqual(VidurRagAnswerParser.clean("**Budget** is open"), "Budget is open")
        XCTAssertEqual(VidurRagAnswerParser.clean("Keep [Q1] labels"), "Keep [Q1] labels")
        XCTAssertEqual(VidurRagAnswerParser.clean("Half a marker [1", streaming: true), "Half a marker")
        XCTAssertEqual(VidurRagAnswerParser.clean("Half a marker [", streaming: true), "Half a marker")
    }

    func testCitationLabelsMapToExistingBlocksOnly() {
        XCTAssertEqual(VidurRagAnswerParser.citedBlocks(["c2", "c9", "c2", "x", "c1"], blockCount: 3), [2, 1])
        XCTAssertEqual(VidurRagAnswerParser.citedBlocks([], blockCount: 3), [])
        XCTAssertEqual(VidurRagAnswerParser.citedBlocks(["c0", "c-1", "C3"], blockCount: 3), [3])
    }

    func testFullJSONRoundTripsThroughTheSharedParser() throws {
        let data = Data("{\"answer\":\"Launch is on 20 November.\",\"citations\":[\"c2\",\"c4\"],\"found\":true}".utf8)
        let parsed = try XCTUnwrap(VidurGroundedParser.parse(data))
        XCTAssertEqual(parsed.answer, "Launch is on 20 November.")
        XCTAssertEqual(VidurRagAnswerParser.citedBlocks(parsed.citationLabels, blockCount: 5), [2, 4])
        XCTAssertTrue(parsed.found)
    }

    // MARK: Sources

    private func result(question: String, cited: [Int], found: Bool = true) -> VidurRagModelResult {
        let retrieval = VidurRagTestSupport.retrieve(question)
        let input = VidurRagPromptInput(question: question, userName: "Neha Sharma", now: VidurEvalFixtures.now,
                                        calendar: VidurEvalFixtures.calendar, retrieval: retrieval)
        let prompt = VidurRagPromptBuilder.build(input)
        return VidurRagModelResult(answer: "Answer.", found: found, citedBlocks: cited, prompt: prompt,
                                   usedWarmSession: true, truncated: false)
    }

    func testCitedBlocksBecomeSourcesWithMeetingAndMoment() throws {
        let base = result(question: "What did we decide on launch?", cited: [])
        let numbers = base.prompt.blocks.filter { $0.chunk.kind == .decision }.map(\.number)
        let number = try XCTUnwrap(numbers.first)
        let cited = result(question: "What did we decide on launch?", cited: [number])
        let sources = VidurRagCitations.sources(for: cited)
        XCTAssertFalse(sources.inferred)
        XCTAssertEqual(sources.items.count, 1)
        let item = try XCTUnwrap(sources.items.first)
        XCTAssertEqual(item.blockNumber, number)
        XCTAssertEqual(item.label, "Decision")
        XCTAssertNotNil(item.timestamp)
        XCTAssertFalse(item.meetingTitle.isEmpty)
        XCTAssertFalse(item.quote.isEmpty)
    }

    func testTranscriptSourcesPointAtTheBestSpokenLine() throws {
        let base = result(question: "Who said the marketing budget is not decided?", cited: [])
        let block = try XCTUnwrap(base.prompt.blocks.first { $0.chunk.kind == .transcript && $0.body.contains("marketing budget") })
        let sources = VidurRagCitations.sources(for: result(question: "Who said the marketing budget is not decided?", cited: [block.number]))
        let item = try XCTUnwrap(sources.items.first)
        XCTAssertNil(item.label)
        XCTAssertEqual(item.timestamp, 300)
        XCTAssertEqual(item.speaker, "Maya Rao")
        XCTAssertEqual(item.meetingTitle, "Launch readiness")
    }

    func testUncitedAnswerFallsBackToTheBestBlocksAndSaysSo() {
        let sources = VidurRagCitations.sources(for: result(question: "What did we decide on launch?", cited: []))
        XCTAssertTrue(sources.inferred)
        XCTAssertFalse(sources.items.isEmpty)
        XCTAssertLessThanOrEqual(sources.items.count, 2)
    }

    func testNotFoundAnswersCarryNoSources() {
        let sources = VidurRagCitations.sources(for: result(question: "What did we decide on launch?", cited: [], found: false))
        XCTAssertTrue(sources.items.isEmpty)
        XCTAssertFalse(sources.inferred)
    }

    func testFactsOnlyCitationIsKeptWhenNothingElseIsCited() {
        let sources = VidurRagCitations.sources(for: result(question: "What did we decide on launch?", cited: [1]))
        XCTAssertEqual(sources.items.count, 1)
        XCTAssertEqual(sources.items.first?.label, "Meeting facts")
        XCTAssertFalse(sources.inferred)
    }

    // MARK: Guard

    func testNamesAndLargeNumbersMustAppearInTheEvidence() {
        let evidence = ["Action: Prepare the agenda | owner: Pawan Kumar | due: Fri 14 Nov"]
        XCTAssertTrue(VidurRagGuard.isFaithful(answer: "Pawan Kumar has to prepare the agenda by 14 Nov.", evidence: evidence))
        XCTAssertTrue(VidurRagGuard.isFaithful(answer: "You have 3 open tasks, and Pawan owns one.", evidence: evidence))
        XCTAssertEqual(VidurRagGuard.unsupportedTerms(in: "Then Rahul will send 45 files.", evidence: evidence).sorted(), ["45", "Rahul"])
        XCTAssertFalse(VidurRagGuard.isFaithful(answer: "It is due on 28 Nov.", evidence: evidence))
    }

    func testRomanNamesMatchDevanagariEvidence() {
        let evidence = ["Owner: \u{092A}\u{0935}\u{0928}. Task: vendor payment."]
        XCTAssertTrue(VidurRagGuard.isFaithful(answer: "Then Pawan clears the vendor payment.", evidence: evidence))
        XCTAssertFalse(VidurRagGuard.isFaithful(answer: "Then Rohit clears it.", evidence: evidence))
    }

    func testWeekdaysMonthsAndSentenceStartsAreNotFlagged() {
        XCTAssertTrue(VidurRagGuard.isFaithful(answer: "Sure. It is due Friday, 5 days after Monday in November.", evidence: ["Nothing here"]))
        XCTAssertTrue(VidurRagGuard.isFaithful(answer: "Fri and Nov are fine.", evidence: ["x"]))
    }

    func testRewriteMustKeepTheVerifiedFacts() {
        let verified = "Launch on 20 November. Pawan Kumar owns the agenda."
        XCTAssertTrue(VidurRagGuard.keepsFacts(answer: "The launch is on 20 November and Pawan Kumar has the agenda.", verified: verified))
        XCTAssertFalse(VidurRagGuard.keepsFacts(answer: "The launch is on 20 November.", verified: verified))
        XCTAssertFalse(VidurRagGuard.keepsFacts(answer: "Pawan Kumar has the agenda.", verified: verified))
    }

    // MARK: Routing

    func testOpenEndedQuestionsGoToTheModel() {
        for question in ["What were the main concerns?", "How did the launch discussion go?", "Tell me about the vendor talks",
                         "What happened in the budget meeting?", "What was the mood in the review?",
                         "Launch meeting kaisa raha?", "What are the pros and cons of the Pune vendor?"] {
            XCTAssertTrue(VidurRagRouting.isOpenEnded(question), question)
        }
    }

    func testFactualQuestionsStayWithTheSavedMinutes() {
        for question in ["When does the pricing page launch?", "How many tasks do I have?", "What did we decide?",
                         "Who attended the hiring review?", "How long was the design review?", "Which tasks are overdue?"] {
            XCTAssertFalse(VidurRagRouting.isOpenEnded(question), question)
        }
    }

    func testOnlyShortRepliesAreRewritten() {
        XCTAssertTrue(VidurRagRouting.canRephrase("Present (2): Neha Sharma, Arjun Mehta."))
        XCTAssertFalse(VidurRagRouting.canRephrase(""))
        XCTAssertFalse(VidurRagRouting.canRephrase(String(repeating: "word ", count: 100)))
        XCTAssertFalse(VidurRagRouting.canRephrase("a\nb\nc\nd\ne\nf"))
    }
}
