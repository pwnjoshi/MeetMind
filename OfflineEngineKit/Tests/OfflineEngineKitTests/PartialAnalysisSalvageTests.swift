import XCTest
@testable import OfflineEngineKit

final class PartialAnalysisSalvageTests: XCTestCase {
    private let point = #"{"text":"Launch is set for 20 November.","evidence":[{"turnID":"t1","quote":"20 November"}]}"#
    private let task = #"{"title":"Prepare the agenda","category":"Create/Update","owner":"Pawan","deadlineText":"by Friday","priority":null,"evidence":[{"turnID":"t2","quote":"agenda"}]}"#

    func testKeepsFinishedItemsWhenTasksAreCutOff() throws {
        let text = #"{"discussion":["# + point + #"],"decisions":[],"tasks":["# + task + #",{"title":"Send the deck","categ"#
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(Data(text.utf8)))
        XCTAssertEqual(result.discussion.count, 1)
        XCTAssertEqual(result.tasks.map(\.title), ["Prepare the agenda"])
        XCTAssertEqual(result.tasks.first?.owner, "Pawan")
    }

    func testMissingSectionsBecomeEmpty() throws {
        let text = #"{"discussion":["# + point + "," + point.dropLast(10)
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(Data(text.utf8)))
        XCTAssertEqual(result.discussion.count, 1)
        XCTAssertTrue(result.decisions.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testBracesInsideStringsAreIgnored() throws {
        let tricky = #"{"text":"Use {braces} and [brackets] \"safely\".","evidence":[{"turnID":"t1","quote":"x"}]}"#
        let text = #"{"discussion":["# + tricky + #",{"text":"unfinished"#
        let result = try XCTUnwrap(PartialAnalysisSalvage.salvage(Data(text.utf8)))
        XCTAssertEqual(result.discussion.first?.text, #"Use {braces} and [brackets] "safely"."#)
    }

    func testNothingFinishedReturnsNil() {
        XCTAssertNil(PartialAnalysisSalvage.salvage(Data(#"{"discussion":[{"text":"half"#.utf8)))
        XCTAssertNil(PartialAnalysisSalvage.salvage(Data()))
    }
}
