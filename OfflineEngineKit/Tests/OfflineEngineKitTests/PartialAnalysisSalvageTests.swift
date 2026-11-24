import XCTest
@testable import OfflineEngineKit

/// Inputs are complete model output (built from dictionaries) cut at a marker, the way a token limit
/// cuts generation.
final class PartialAnalysisSalvageTests: XCTestCase {
    private func evidence(_ turn: String, _ quote: String) -> [[String: Any]] {
        [["turnID": turn, "quote": quote]]
    }

    private func point(_ text: String) -> [String: Any] {
        ["text": text, "evidence": evidence("t1", "quote")]
    }

    private func task(_ title: String, owner: Any) -> [String: Any] {
        ["title": title, "category": "Follow-up", "owner": owner, "deadlineText": NSNull(), "priority": NSNull(),
         "evidence": evidence("t2", "quote")]
    }

    /// Sorted keys put "evidence" before "text", so a cut can leave an item with evidence but no text;
    /// the salvager must skip that item and fall back to the last fully decodable one.
    private func output(discussion: [[String: Any]], decisions: [[String: Any]] = [],
                        tasks: [[String: Any]] = []) throws -> String {
        let object: [String: Any] = ["discussion": discussion, "decisions": decisions, "tasks": tasks]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func cut(_ text: String, before marker: String) -> Data {
        guard let range = text.range(of: marker) else { return Data(text.utf8) }
        return Data(text[..<range.lowerBound].utf8)
    }

    func testKeepsFinishedItemsWhenTheLastItemIsCutOff() throws {
        let full = try output(discussion: [point("Launch is set for 20 November.")],
                              tasks: [task("Prepare the agenda", owner: "Pawan"), task("Send the deck", owner: NSNull())])
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(cut(full, before: "Send the deck")))
        XCTAssertEqual(result.discussion.count, 1)
        XCTAssertEqual(result.tasks.map(\.title), ["Prepare the agenda"])
        XCTAssertEqual(result.tasks.first?.owner, "Pawan")
    }

    func testMissingSectionsBecomeEmpty() throws {
        // Sorted keys put "decisions" first; cutting inside the second discussion point drops "tasks".
        let full = try output(discussion: [point("Launch is set."), point("Budget is still open.")])
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(cut(full, before: "still open")))
        XCTAssertEqual(result.discussion.map(\.text), ["Launch is set."])
        XCTAssertTrue(result.decisions.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testBracketsInsideStringsAreIgnored() throws {
        let tricky = "Use \u{7B}braces\u{7D} and \u{5B}brackets\u{5D} \u{22}safely\u{22}."
        let full = try output(discussion: [point(tricky), point("Second point.")])
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(cut(full, before: "Second point")))
        XCTAssertEqual(result.discussion.first?.text, tricky)
    }

    func testNothingFinishedReturnsNil() throws {
        let full = try output(discussion: [point("Launch is set.")])
        XCTAssertNil(PartialAnalysisSalvage.salvage(cut(full, before: "Launch is set")))
        XCTAssertNil(PartialAnalysisSalvage.salvage(Data()))
    }
}
