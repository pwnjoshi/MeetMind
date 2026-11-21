import XCTest
@testable import OfflineEngineKit

final class AnalysisSanitizationTests: XCTestCase {
    private let turns = [
        AnalysisTurn(id: "t1", text: "Rahul will send the estimate tomorrow.", start: 0, end: 2, speaker: nil),
        AnalysisTurn(id: "t2", text: "We have not decided to change the design.", start: 2, end: 4, speaker: nil)
    ]

    func testCopiedPromptExampleIsDroppedWhileGroundedItemsSurvive() {
        let grounded = SuggestedTask(title: "Send the estimate", category: "Follow-up", owner: "Rahul",
                                     deadlineText: "tomorrow", priority: nil,
                                     evidence: [SourceEvidence(turnID: "t1", quote: "Rahul will send the estimate tomorrow")])
        // A small model copying the prompt example: the quote is not in the transcript.
        let copied = SuggestedTask(title: "Prepare the agenda", category: "Create/Update", owner: "Pawan",
                                   deadlineText: "by Friday", priority: nil,
                                   evidence: [SourceEvidence(turnID: "t1", quote: "Pawan, can you prepare the agenda by Friday?")])
        let invented = SupportedPoint(text: "The Pune vendor is selected.",
                                      evidence: [SourceEvidence(turnID: "t2", quote: "Let's go with the Pune vendor.")])
        let raw = LocalAnalysisResult(discussion: [], decisions: [invented], tasks: [grounded, copied])

        let clean = raw.sanitized(against: turns)

        XCTAssertEqual(clean.tasks.map(\.title), ["Send the estimate"])
        XCTAssertTrue(clean.decisions.isEmpty)
        XCTAssertNoThrow(try clean.validate(against: turns))
    }

    func testInvalidCategoryUnknownTurnAndEmptyTextAreDropped() {
        let badCategory = SuggestedTask(title: "Send", category: "Misc", owner: nil, deadlineText: nil, priority: nil,
                                        evidence: [SourceEvidence(turnID: "t1", quote: "send")])
        let unknownTurn = SupportedPoint(text: "Design", evidence: [SourceEvidence(turnID: "t9", quote: "design")])
        let empty = SupportedPoint(text: "  ", evidence: [SourceEvidence(turnID: "t2", quote: "design")])
        let raw = LocalAnalysisResult(discussion: [unknownTurn, empty], decisions: [], tasks: [badCategory])

        let clean = raw.sanitized(against: turns)

        XCTAssertTrue(clean.tasks.isEmpty)
        XCTAssertTrue(clean.discussion.isEmpty)
    }
}
