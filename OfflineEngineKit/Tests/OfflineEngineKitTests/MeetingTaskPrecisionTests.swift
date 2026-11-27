import XCTest
@testable import OfflineEngineKit

/// Precision regressions for the public synthetic fixture: exactly one task,
/// no decision, and one open issue.
final class MeetingTaskPrecisionTests: XCTestCase {
    private let fixtureText = "Rahul will send the estimate tomorrow. We have not decided to change the design."

    private func checkpoint(turns: [AnalysisTurn], analysis: [LocalAnalysisResult]) -> MeetingAnalysisCheckpoint {
        MeetingAnalysisCheckpoint(sourceSignature: "fixture", stage: .completed, turns: turns,
                                  speakers: [], analysis: analysis, analyzedChunks: analysis.count)
    }

    private func task(_ title: String, owner: String? = nil, deadline: String? = nil,
                      turn: String = "t1", quote: String) -> SuggestedTask {
        SuggestedTask(title: title, category: "Follow-up", owner: owner, deadlineText: deadline, priority: nil,
                      evidence: [SourceEvidence(turnID: turn, quote: quote)])
    }

    private func point(_ text: String, turn: String = "t1", quote: String) -> SupportedPoint {
        SupportedPoint(text: text, evidence: [SourceEvidence(turnID: turn, quote: quote)])
    }

    func testFixtureWithEmptyModelOutputYieldsOneTaskNoDecisionOneOpenIssue() throws {
        let turn = AnalysisTurn(id: "t1", text: fixtureText, start: 0, end: 6, speaker: nil)
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])]))
        XCTAssertEqual(reduced.tasks.count, 1)
        let only = try XCTUnwrap(reduced.tasks.first)
        XCTAssertEqual(only.title, "Send the estimate")
        XCTAssertEqual(only.owner, "Rahul")
        XCTAssertEqual(only.deadlineText?.lowercased(), "tomorrow")
        XCTAssertTrue(reduced.decisions.isEmpty)
        XCTAssertEqual(reduced.openIssues.count, 1)
        XCTAssertTrue(reduced.openIssues[0].text.contains("not decided"))
    }

    func testFixtureWithHallucinatedModelOutputStillYieldsExactlyOneTask() throws {
        let turn = AnalysisTurn(id: "t1", text: fixtureText, start: 0, end: 6, speaker: nil)
        let hallucinated = LocalAnalysisResult(
            discussion: [point("The team discussed changing the design.", quote: "change the design")],
            decisions: [point("The design will be changed.", quote: "change the design")],
            tasks: [
                task("Send the estimate", quote: "send the estimate"),
                task("Change the design", quote: "change the design"),
                task("Decide on the design change", quote: "We have not decided to change the design."),
                task("Send estimate to client", owner: "Rahul", deadline: "tomorrow", quote: "Rahul will send the estimate tomorrow."),
                task("Prepare design plan", quote: fixtureText)
            ])
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [hallucinated]))
        XCTAssertEqual(reduced.tasks.count, 1, "\(reduced.tasks.map(\.title))")
        let only = try XCTUnwrap(reduced.tasks.first)
        XCTAssertEqual(only.owner, "Rahul")
        XCTAssertEqual(only.deadlineText?.lowercased(), "tomorrow")
        XCTAssertTrue(reduced.decisions.isEmpty)
        XCTAssertEqual(reduced.openIssues.count, 1, "\(reduced.openIssues.map(\.text))")
        XCTAssertTrue(reduced.discussion.isEmpty)
    }

    func testFixtureAsSeparateTurnsWithHallucinatedFragmentQuotes() {
        let turns = [
            AnalysisTurn(id: "t1", text: "Rahul will send the estimate tomorrow.", start: 0, end: 3, speaker: "Speaker 1"),
            AnalysisTurn(id: "t2", text: "We have not decided to change the design.", start: 3, end: 6, speaker: "Speaker 2")
        ]
        let model = LocalAnalysisResult(
            discussion: [], decisions: [point("Design change decided.", turn: "t2", quote: "decided to change the design")],
            tasks: [task("Change the design", turn: "t2", quote: "change the design"),
                    task("Decide design change", turn: "t2", quote: "have not decided")])
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns, analysis: [model]))
        XCTAssertEqual(reduced.tasks.map(\.title), ["Send the estimate"])
        XCTAssertTrue(reduced.decisions.isEmpty)
        XCTAssertEqual(reduced.openIssues.count, 1)
    }

    func testHinglishFixtureVariants() throws {
        let text = "Rahul kal tak estimate bhej dega. Design change abhi decide nahi hua."
        let turn = AnalysisTurn(id: "t1", text: text, start: 0, end: 6, speaker: nil)
        let model = LocalAnalysisResult(discussion: [], decisions: [],
            tasks: [task("Change design", quote: "Design change"),
                    task("Decide design change", quote: "Design change abhi decide nahi hua.")])
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [model]))
        XCTAssertEqual(reduced.tasks.count, 1, "\(reduced.tasks.map(\.title))")
        let only = try XCTUnwrap(reduced.tasks.first)
        XCTAssertEqual(only.title, "Send estimate")
        XCTAssertEqual(only.owner, "Rahul")
        XCTAssertEqual(only.deadlineText?.lowercased(), "kal tak")
        XCTAssertEqual(only.evidence.first?.quote, "Rahul kal tak estimate bhej dega.")
        XCTAssertTrue(reduced.decisions.isEmpty)
        XCTAssertEqual(reduced.openIssues.count, 1)
    }

    func testNegatedAndHypotheticalCommitmentsAreRejectedForModelTasks() {
        let sentences = [
            "Maria will not send the report this week.",
            "Maybe Dev will send the report.",
            "Should we send the report to finance?",
            "Dev might send the report on Friday.",
            "The report task is cancelled.",
            "Could we send the report on Monday?",
            "Amit report bhejega nahi."
        ]
        for (index, sentence) in sentences.enumerated() {
            let turn = AnalysisTurn(id: "t\(index)", text: sentence, start: 0, end: 1, speaker: nil)
            let model = LocalAnalysisResult(discussion: [], decisions: [],
                tasks: [task("Send the report", turn: turn.id, quote: sentence)])
            let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [model]))
            XCTAssertTrue(reduced.tasks.isEmpty, "Should not create a task from: \(sentence)")
        }
    }

    func testUndecidedMarkersNeverProduceDecisions() {
        let sentences = [
            "We haven't decided on the vendor.",
            "There is no decision about pricing yet.",
            "Should we move the launch?",
            "Maybe we approve the budget next month.",
            "Vendor abhi decide nahi hua."
        ]
        for (index, sentence) in sentences.enumerated() {
            let turn = AnalysisTurn(id: "t\(index)", text: sentence, start: 0, end: 1, speaker: nil)
            let model = LocalAnalysisResult(discussion: [],
                decisions: [point("The team decided the matter.", turn: turn.id, quote: sentence)], tasks: [])
            let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [model]))
            XCTAssertTrue(reduced.decisions.isEmpty, "Should not decide from: \(sentence)")
            XCTAssertEqual(reduced.openIssues.count, 1, "Open issue expected for: \(sentence)")
        }
    }

    func testDefiniteDecisionStillSurvivesNextToUndecidedSentence() {
        let turn = AnalysisTurn(id: "t1", text: "We agreed to launch on 20 November. We have not decided to change the design.",
                                start: 0, end: 5, speaker: nil)
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])]))
        XCTAssertEqual(reduced.decisions.count, 1)
        XCTAssertTrue(reduced.decisions[0].text.contains("launch"))
        XCTAssertEqual(reduced.openIssues.count, 1)
    }

    func testTasksSharingEvidenceAndActionTokensMergePreferringOwnerAndDeadline() throws {
        let turn = AnalysisTurn(id: "t1", text: "Priya will share the budget sheet by Friday.", start: 0, end: 3, speaker: nil)
        let quote = "Priya will share the budget sheet by Friday."
        let model = LocalAnalysisResult(discussion: [], decisions: [], tasks: [
            task("Share budget", quote: quote),
            task("Provide the budget sheet to finance", owner: "Priya", deadline: "by Friday", quote: quote)
        ])
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [model]))
        XCTAssertEqual(reduced.tasks.count, 1, "\(reduced.tasks.map(\.title))")
        let only = try XCTUnwrap(reduced.tasks.first)
        XCTAssertEqual(only.owner, "Priya")
        XCTAssertEqual(only.deadlineText, "by Friday")
    }

    func testDistinctTasksInDifferentTurnsAreNotMerged() {
        let turns = [
            AnalysisTurn(id: "t1", text: "Rahul will send the estimate tomorrow.", start: 0, end: 2, speaker: nil),
            AnalysisTurn(id: "t2", text: "Maya will review the contract on Friday.", start: 2, end: 4, speaker: nil)
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns, analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])]))
        XCTAssertEqual(reduced.tasks.count, 2)
    }

    func testOldCheckpointWithoutOpenIssuesStillDecodes() throws {
        let json = #"{"discussion":[{"text":"A point","evidence":[{"turnID":"t1","quote":"q"}]}],"decisions":[],"tasks":[]}"#
        let decoded = try JSONDecoder().decode(LocalAnalysisResult.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.discussion.count, 1)
        XCTAssertTrue(decoded.openIssues.isEmpty)
        let round = try JSONDecoder().decode(LocalAnalysisResult.self,
            from: JSONEncoder().encode(LocalAnalysisResult(discussion: [], decisions: [], tasks: [],
                openIssues: [point("Open", quote: "q")])))
        XCTAssertEqual(round.openIssues.count, 1)
    }

    func testOldCheckpointBlobWithoutOpenIssuesDecodesAsCheckpoint() throws {
        let json = #"{"sourceSignature":"s","stage":"completed","turns":[],"speakers":[],"analysis":[{"discussion":[],"decisions":[],"tasks":[]}],"analyzedChunks":1}"#
        let decoded = try JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.analysis.count, 1)
        XCTAssertTrue(decoded.analysis[0].openIssues.isEmpty)
    }
}
