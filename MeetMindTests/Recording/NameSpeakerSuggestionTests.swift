import XCTest
@testable import MeetMind

final class NameSpeakerSuggestionTests: XCTestCase {
    func testParsesSuggestedAttendeesFromMinutes() throws {
        let json: [String: Any] = [
            "minutes": [
                "suggestedAttendees": [
                    ["name": "Maya Rao", "reason": "Addressed by Arjun", "evidence": [["turnID": 3, "quote": "Maya, can you"]]],
                    ["name": "  Arjun Mehta ", "reason": ""],
                    ["name": "maya rao", "reason": "duplicate"],
                    ["name": "   ", "reason": "blank"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = NameSpeakerSuggestion.parse(data)
        XCTAssertEqual(result.map(\.name), ["Maya Rao", "Arjun Mehta"])
        XCTAssertEqual(result.first?.reason, "Addressed by Arjun")
    }

    func testMissingOrMalformedDataYieldsNoSuggestions() throws {
        XCTAssertTrue(NameSpeakerSuggestion.parse(nil).isEmpty)
        XCTAssertTrue(NameSpeakerSuggestion.parse(Data("not json".utf8)).isEmpty)
        let noMinutes = try JSONSerialization.data(withJSONObject: ["other": 1])
        XCTAssertTrue(NameSpeakerSuggestion.parse(noMinutes).isEmpty)
    }
}
