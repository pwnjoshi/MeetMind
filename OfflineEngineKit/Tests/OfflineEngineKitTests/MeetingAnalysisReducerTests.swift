import XCTest
@testable import OfflineEngineKit

final class MeetingAnalysisReducerTests: XCTestCase {
    private func checkpoint(turns: [AnalysisTurn], analysis: [LocalAnalysisResult]) -> MeetingAnalysisCheckpoint {
        MeetingAnalysisCheckpoint(sourceSignature: "fixture", stage: .completed, turns: turns,
                                  speakers: [], analysis: analysis, analyzedChunks: analysis.count)
    }

    func testExplicitCommitmentBecomesGroundedReviewableTaskWhenModelMissesIt() throws {
        let text = "Rahul will send the estimate tomorrow."
        let turn = AnalysisTurn(id: "t1", text: text, start: 0, end: 3, speaker: "Rahul")
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
        ]))

        let task = try XCTUnwrap(reduced.tasks.first)
        XCTAssertEqual(task.title, "Send the estimate")
        XCTAssertEqual(task.owner, "Rahul")
        XCTAssertEqual(task.deadlineText?.lowercased(), "tomorrow")
        XCTAssertEqual(task.evidence.first?.turnID, "t1")
        XCTAssertEqual(task.evidence.first?.quote, text)
        XCTAssertEqual(reduced.checkpoint.analysis.first?.tasks.count, 1)
    }

    func testNegatedOrCancelledCommitmentIsNeverSupplemented() {
        let turns = [
            AnalysisTurn(id: "t1", text: "Rahul will not send the estimate tomorrow.", start: 0, end: 2, speaker: "Rahul"),
            AnalysisTurn(id: "t2", text: "Maya will prepare the draft, but that task is cancelled.", start: 2, end: 5, speaker: "Maya")
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns, analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
        ]))
        XCTAssertTrue(reduced.tasks.isEmpty)
    }

    func testExplicitDecisionAndUnresolvedOutcomeAreSeparated() {
        let turns = [
            AnalysisTurn(id: "t1", text: "We agreed to launch on 20 November.", start: 0, end: 2, speaker: nil),
            AnalysisTurn(id: "t2", text: "We have not decided to change the design.", start: 2, end: 4, speaker: nil)
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns, analysis: [
            LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
        ]))
        XCTAssertEqual(reduced.decisions.count, 1)
        XCTAssertTrue(reduced.decisions[0].text.contains("launch"))
        XCTAssertTrue(reduced.discussion.isEmpty)
        XCTAssertEqual(reduced.openIssues.count, 1)
        XCTAssertTrue(reduced.openIssues[0].text.contains("not decided"))
    }

    func testChunkParaphrasesAreReducedToOneMinutesPointWithCombinedEvidence() {
        let turns = [
            AnalysisTurn(id: "t1", text: "The launch budget remains pending Finance review.", start: 0, end: 2, speaker: nil),
            AnalysisTurn(id: "t2", text: "Finance must still review the pending launch budget.", start: 2, end: 4, speaker: nil)
        ]
        let analysis = [
            LocalAnalysisResult(discussion: [SupportedPoint(text: "The launch budget remains pending Finance review",
                evidence: [SourceEvidence(turnID: "t1", quote: turns[0].text)])], decisions: [], tasks: []),
            LocalAnalysisResult(discussion: [SupportedPoint(text: "Finance review of the launch budget remains pending.",
                evidence: [SourceEvidence(turnID: "t2", quote: turns[1].text)])], decisions: [], tasks: [])
        ]
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: turns, analysis: analysis))
        XCTAssertEqual(reduced.discussion.count, 1)
        XCTAssertEqual(reduced.discussion[0].evidence.count, 2)
        XCTAssertFalse(reduced.executiveSummary.isEmpty)
    }

    func testGreetingsAndEmptyModelOutputProduceTruthfulEmptySummary() {
        let turn = AnalysisTurn(id: "t1", text: "Hello. Thank you.", start: 0, end: 2, speaker: nil)
        let analysis = LocalAnalysisResult(
            discussion: [SupportedPoint(text: "Thank you", evidence: [SourceEvidence(turnID: "t1", quote: "Thank you")])],
            decisions: [], tasks: [])
        let reduced = MeetingAnalysisReducer.reduce(checkpoint(turns: [turn], analysis: [analysis]))
        XCTAssertTrue(reduced.discussion.isEmpty)
        XCTAssertEqual(reduced.executiveSummary, "No substantive meeting outcomes were identified.")
    }
}
