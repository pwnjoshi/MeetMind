import XCTest
import Foundation
@testable import MeetMind

final class AgendaPointsTests: XCTestCase {
    func testParseStripsListMarkersAndBlankLines() {
        let text = "1. Budget\n- Hiring\n\u{2022} Roadmap\n* Risks\n2) Next steps\n\n   \nPlain line"
        XCTAssertEqual(
            AgendaPoints.parse(text),
            ["Budget", "Hiring", "Roadmap", "Risks", "Next steps", "Plain line"]
        )
    }

    func testParseKeepsNumbersThatAreNotMarkers() {
        XCTAssertEqual(AgendaPoints.parse("2025 plan\n1.5x speed"), ["2025 plan", "1.5x speed"])
    }

    func testJoinWritesOnePointPerLineAndDropsEmptyOnes() {
        XCTAssertEqual(AgendaPoints.join(["  Budget ", "", "Hiring", "   "]), "Budget\nHiring")
        XCTAssertEqual(AgendaPoints.join([]), "")
    }

    func testParseThenJoinRoundTrips() {
        let stored = "Budget\nHiring\nRoadmap"
        XCTAssertEqual(AgendaPoints.join(AgendaPoints.parse(stored)), stored)
    }

    func testSplitSentences() {
        XCTAssertEqual(
            AgendaPoints.splitSentences("Review the budget. Who owns hiring? Agree next steps!"),
            ["Review the budget", "Who owns hiring?", "Agree next steps!"]
        )
        XCTAssertEqual(AgendaPoints.splitSentences("One sentence only"), ["One sentence only"])
        XCTAssertEqual(AgendaPoints.splitSentences("Version 2.5 rollout. Owners"), ["Version 2.5 rollout", "Owners"])
    }

    func testTypingNeverSplits() {
        XCTAssertNil(AgendaPoints.splitEdit(old: "Budget", new: "Budget r"))
        XCTAssertNil(AgendaPoints.splitEdit(old: "Budget.", new: "Budget. "))
        XCTAssertNil(AgendaPoints.splitEdit(old: "", new: "B"))
    }

    func testPastedParagraphSplitsIntoSentences() {
        let pasted = "Review the budget. Agree hiring plan. Confirm launch date."
        XCTAssertEqual(
            AgendaPoints.splitEdit(old: "", new: pasted),
            ["Review the budget", "Agree hiring plan", "Confirm launch date"]
        )
    }

    func testPastedSingleSentenceDoesNotSplit() {
        XCTAssertNil(AgendaPoints.splitEdit(old: "", new: "Review the budget for next quarter"))
    }

    func testPastedLinesSplitAndStripMarkers() {
        XCTAssertEqual(
            AgendaPoints.splitEdit(old: "", new: "- Budget\n- Hiring\n3. Roadmap"),
            ["Budget", "Hiring", "Roadmap"]
        )
    }

    func testReturnAtTheEndAddsAnEmptyNextPoint() {
        XCTAssertEqual(AgendaPoints.splitEdit(old: "Budget", new: "Budget\n"), ["Budget", ""])
    }

    func testReturnInTheMiddleSplitsAtTheCursor() {
        XCTAssertEqual(AgendaPoints.splitEdit(old: "Budget hiring", new: "Budget\nhiring"), ["Budget", "hiring"])
    }

    func testReturnInAnEmptyPointGivesASingleEmptyEntry() {
        XCTAssertEqual(AgendaPoints.splitEdit(old: "", new: "\n"), [""])
    }
}
