import XCTest
@testable import OfflineEngineKit

/// Regressions found by replaying two private meeting recordings on an iPhone 15 (build e1322df, 2026-11-27).
/// Every sentence here is a synthetic paraphrase with invented names. It keeps the sentence *structure* that
/// failed on device and none of the recorded wording. Do not paste real transcript text into this file.
///
/// Failure classes:
/// 1. Owners: natural assignment phrasing ("you can focus on", "I would recommend that X", "X will be handling",
///    "I would love it if you can") produced no owner. On device, 0 of 13 real assignment sentences matched a rule.
/// 2. Template copies: the model filled in the prompt's examples ("Prepare the document", "the option is
///    approved") with any nearby quote, and the reducer kept them because a quote existed.
/// 3. Questions as decisions: a budget proposal ending in "what do you think?" became an adopted decision.
/// 4. Reassignment: a later swap of two people's tasks must win over the first assignment.
/// 5. Hindi second-person future forms ("samjhogi", "bataogi") as requests.
///
/// These are known gaps, so by default each one is wrapped in a non-strict expected failure. CI then stays green
/// and the IPA still builds, and the test log shows each gap as an "expected failure". Set
/// MEETMIND_ENFORCE_SPOKEN_ASSIGNMENTS=1 to make them hard failures. Remove the wrapper when a gap is fixed.
final class SpokenAssignmentRegressionTests: XCTestCase {
    private var enforce: Bool { ProcessInfo.processInfo.environment["MEETMIND_ENFORCE_SPOKEN_ASSIGNMENTS"] == "1" }

    private func knownGap(_ reason: String, _ body: () throws -> Void) rethrows {
        guard !enforce else { return try body() }
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        try XCTExpectFailure(reason, options: options, failingBlock: body)
    }

    // MARK: Helpers

    private func turn(_ id: String, _ text: String, speaker: String? = nil, at start: Double) -> AnalysisTurn {
        AnalysisTurn(id: id, text: text, start: start, end: start + 4, speaker: speaker)
    }

    private func reduce(_ turns: [AnalysisTurn], model: LocalAnalysisResult = LocalAnalysisResult(discussion: [], decisions: [], tasks: []),
                        participants: [String] = []) -> ReducedMeetingAnalysis {
        let checkpoint = MeetingAnalysisCheckpoint(sourceSignature: "spoken-assignments", stage: .completed, turns: turns,
                                                   speakers: [], analysis: [model], analyzedChunks: 1)
        return MeetingAnalysisReducer.reduce(checkpoint, participants: participants)
    }

    private func task(_ title: String, owner: String? = nil, turn: String, quote: String) -> SuggestedTask {
        SuggestedTask(title: title, category: "Other", owner: owner, deadlineText: nil, priority: nil,
                      evidence: [SourceEvidence(turnID: turn, quote: quote)])
    }

    private func point(_ text: String, turn: String, quote: String) -> SupportedPoint {
        SupportedPoint(text: text, evidence: [SourceEvidence(turnID: turn, quote: quote)])
    }

    private func describe(_ reduced: ReducedMeetingAnalysis) -> String {
        "tasks=\(reduced.tasks.map { "\($0.owner ?? "-"): \($0.title)" }) decisions=\(reduced.decisions.map(\.text))"
    }

    /// The single task owned by `owner` whose title mentions every word in `about`.
    private func assertTask(owner: String, about words: [String], in reduced: ReducedMeetingAnalysis,
                            file: StaticString = #filePath, line: UInt = #line) {
        let match = reduced.tasks.first { task in
            task.owner == owner && words.allSatisfy { task.title.lowercased().contains($0) }
        }
        XCTAssertNotNil(match, "no \(owner) task about \(words); \(describe(reduced))", file: file, line: line)
    }

    // MARK: 1. Owners from natural assignment phrasing (deterministic floor, empty model output)

    /// Fails on the committed build. The working tree's new "you continue" rule should make it pass; it stays
    /// wrapped only until CI confirms that.
    func testVocativeYouContinueAssignsOwner() {
        knownGap("'<Name>, you continue ...' had no rule in build e1322df") {
            let reduced = reduce([turn("t1", "And Neha, you continue with the vendor shortlist, right?", speaker: "S1", at: 0)])
            assertTask(owner: "Neha", about: ["vendor", "shortlist"], in: reduced)
        }
    }

    func testVocativeYouCanWithUnlistedVerbAssignsOwner() {
        knownGap("'you can' + a verb outside the action list (focus) is not a rule") {
            let reduced = reduce([turn("t1", "Arjun, you can focus more on the pricing model, which suits us better.", speaker: "S1", at: 0)])
            assertTask(owner: "Arjun", about: ["pricing"], in: reduced)
        }
    }

    func testRecommendThatNameAssignsOwner() {
        knownGap("'I would recommend that <Name> <verb>s' is not a rule") {
            let reduced = reduce([turn("t1", "However, I would recommend that Maya reviews the onboarding flow and checks two rival apps.",
                                       speaker: "S1", at: 0)])
            assertTask(owner: "Maya", about: ["onboarding"], in: reduced)
        }
    }

    func testForNameIWouldLoveIfYouCanAssignsOwner() {
        knownGap("'For <Name>, I would love it if you can ...' is not a rule") {
            let reduced = reduce([turn("t1", "So for Priya, I would love it if you can finish the dashboard redesign.", speaker: "S1", at: 0)])
            assertTask(owner: "Priya", about: ["dashboard"], in: reduced)
        }
    }

    func testNameWillBeDoingAssignsOwner() {
        knownGap("'<Name> will be <verb>ing ...' fails: 'be' is not an action verb") {
            let reduced = reduce([turn("t1", "Rahul will be handling the model evaluation from now on.", speaker: "S1", at: 0)])
            assertTask(owner: "Rahul", about: ["model", "evaluation"], in: reduced)
        }
    }

    func testLowercaseAsrNameMatchesKnownParticipant() {
        knownGap("speech recognition often lowercases names mid-sentence; the rules require an uppercase first letter") {
            let reduced = reduce([turn("t1", "okay that works, so rahul will take over the backend work.", speaker: "S1", at: 0)],
                                 participants: ["Rahul", "Neha"])
            assertTask(owner: "Rahul", about: ["backend"], in: reduced)
        }
    }

    func testYouAfterVocativeInEarlierSentenceAssignsAddressee() {
        knownGap("a request with 'you' after a vocative in the same turn has no owner") {
            let reduced = reduce([
                turn("t1", "Arjun, thanks for the update. So I want you to find a lighter summarisation model.", speaker: "S1", at: 0)
            ])
            assertTask(owner: "Arjun", about: ["summarisation"], in: reduced)
        }
    }

    /// A manager running through the whole team in one stretch: every person gets an owned task.
    func testTeamRoundupGivesEveryNamedPersonATask() {
        knownGap("only one of four roundup phrasings is covered") {
            let reduced = reduce([
                turn("t1", "However, I would recommend that Maya goes deeper on the checkout flow and rival storefronts.", speaker: "S1", at: 0),
                turn("t2", "Arjun, you can continue focusing on the ranking service.", speaker: "S1", at: 5),
                turn("t3", "And Neha, you continue your survey and narrow down the target schools.", speaker: "S1", at: 10),
                turn("t4", "And Rahul, you continue with the billing prototype, right?", speaker: "S1", at: 15)
            ])
            let owners = Set(reduced.tasks.compactMap(\.owner))
            XCTAssertEqual(owners, ["Maya", "Arjun", "Neha", "Rahul"], describe(reduced))
        }
    }

    // MARK: 2. Template copies from the prompt examples

    func testPromptTemplateTasksWithUnrelatedQuotesAreDropped() {
        knownGap("the committed reducer keeps a task when any quote exists, so template copies leak") {
            let turns = [
                turn("t1", "We should think about both retail stores and online orders.", speaker: "S1", at: 0),
                turn("t2", "Yes, that works for me.", speaker: "S2", at: 5)
            ]
            let model = LocalAnalysisResult(discussion: [], decisions: [], tasks: [
                task("Prepare the document", turn: "t1", quote: "retail stores and online orders"),
                task("Prepare the document on retail stores and online orders", turn: "t1",
                     quote: "We should think about both retail stores and online orders."),
                task("Tell you", turn: "t2", quote: "that works for me")
            ])
            let reduced = reduce(turns, model: model)
            XCTAssertTrue(reduced.tasks.isEmpty, describe(reduced))
        }
    }

    func testNextMeetingTimeIsNotATask() {
        knownGap("a stated next-meeting time became a 'Prepare the next meeting' task") {
            let turns = [turn("t1", "Good, that covers it, and we'll meet again for the next meeting on Monday at 4pm.", speaker: "S1", at: 0)]
            let model = LocalAnalysisResult(discussion: [], decisions: [], tasks: [
                task("Prepare the next meeting at 4pm", turn: "t1", quote: "the next meeting on Monday at 4pm")
            ])
            let reduced = reduce(turns, model: model)
            XCTAssertFalse(reduced.tasks.contains { $0.title.lowercased().contains("next meeting") }, describe(reduced))
        }
    }

    func testTemplateDecisionWithoutSettlementIsDropped() {
        knownGap("a model decision whose quote settles nothing is kept as an adopted resolution") {
            let turns = [
                turn("t1", "Also compare the rival checkout pages, because the payment screen matters a lot.", speaker: "S1", at: 0),
                turn("t2", "Later the team could port it to Kotlin.", speaker: "S1", at: 5)
            ]
            let model = LocalAnalysisResult(discussion: [], decisions: [
                point("The Figma approach for the payment screen is approved.", turn: "t1", quote: "the payment screen matters a lot"),
                point("The plan to port the app to Kotlin is approved.", turn: "t2", quote: "port it to Kotlin")
            ], tasks: [])
            let reduced = reduce(turns, model: model)
            XCTAssertTrue(reduced.decisions.isEmpty, describe(reduced))
        }
    }

    // MARK: 3. Questions are not decisions

    func testBudgetProposalAskedAsQuestionIsNotADecision() {
        knownGap("a budget proposal ending in a question became an adopted decision") {
            let turns = [
                turn("t1", "So Arjun, let us keep 45,000 aside for the pilot, how does that sound?", speaker: "S1", at: 0),
                turn("t2", "I'd rather talk about who does what first.", speaker: "S2", at: 5)
            ]
            let model = LocalAnalysisResult(discussion: [], decisions: [
                point("The pilot and a budget of 45,000 are approved.", turn: "t1", quote: "keep 45,000 aside for the pilot")
            ], tasks: [])
            let reduced = reduce(turns, model: model)
            XCTAssertFalse(reduced.decisions.contains { $0.text.contains("45,000") }, describe(reduced))
        }
    }

    // MARK: 4. Reassignment

    func testLaterSwapOverridesFirstAssignment() {
        knownGap("a later swap of two people's work must replace the first assignment") {
            let turns = [
                turn("t1", "Neha, can you complete the interface redesign?", speaker: "S1", at: 0),
                turn("t2", "Actually I want the interface work, and Neha should get the backend. Can you reassign it?", speaker: "S2", at: 5),
                turn("t3", "Alright, that works. Arjun, you will do the interface work and Neha will do the model research.", speaker: "S1", at: 10)
            ]
            let reduced = reduce(turns, participants: ["Neha", "Arjun"])
            assertTask(owner: "Arjun", about: ["interface"], in: reduced)
            XCTAssertFalse(reduced.tasks.contains { $0.owner == "Neha" && $0.title.lowercased().contains("interface") },
                           describe(reduced))
        }
    }

    // MARK: 5. Hindi second-person future requests

    func testDevanagariSecondPersonFutureRequestIsATask() {
        knownGap("second-person future forms (समझोगी, बताओगी) are not request cues") {
            let reduced = reduce([
                turn("t1", "नेहा, तुम कल पेमेंट फ्लो को ध्यान से समझोगी और फिर हमें बताओगी, ठीक है?", speaker: "S1", at: 0)
            ])
            XCTAssertFalse(reduced.tasks.isEmpty, describe(reduced))
            XCTAssertNotNil(reduced.tasks.first?.owner, describe(reduced))
        }
    }
}
