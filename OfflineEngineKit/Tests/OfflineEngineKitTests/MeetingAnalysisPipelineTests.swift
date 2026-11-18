import XCTest
@testable import OfflineEngineKit

final class MeetingAnalysisPipelineTests: XCTestCase {
    func testOverlappingSpeakersAreNotGuessed() {
        let turn = AnalysisTurn(id: "t1", text: "Mixed speech", start: 0, end: 10, speaker: nil)
        let spans = [SpeakerSpan(speaker: "A", start: 0, end: 8),
                     SpeakerSpan(speaker: "B", start: 4, end: 10)]
        XCTAssertNil(MeetingAnalysisPipeline.assignSpeakers(turns: [turn], spans: spans)[0].speaker)
    }

    func testClearSpeakerAndSilence() {
        let turns = [AnalysisTurn(id: "t1", text: "Hello", start: 0, end: 5, speaker: nil),
                     AnalysisTurn(id: "t2", text: "Quiet", start: 10, end: 15, speaker: nil)]
        let result = MeetingAnalysisPipeline.assignSpeakers(turns: turns,
            spans: [SpeakerSpan(speaker: "A", start: 0, end: 5)])
        XCTAssertEqual(result[0].speaker, "A")
        XCTAssertNil(result[1].speaker)
    }

    func testLongHinglishTurnIsPreservedAndBounded() {
        let text = String(repeating: "कल estimate भेज देना। ", count: 250)
        let chunks = MeetingAnalysisPipeline.analysisChunks([
            AnalysisTurn(id: "t1", text: text, start: 0, end: 600, speaker: nil)])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.reduce(0) { $0 + $1.text.count } <= 1600 })
        var seen = Set<String>()
        let unique = chunks.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        XCTAssertEqual(unique.map(\.text).joined(), text)
    }

    func testChunksRetainContextWithoutDuplicateIDsWithinChunk() {
        let turns = (0..<20).map {
            AnalysisTurn(id: "t\($0)", text: String(repeating: "a", count: 500), start: Double($0), end: Double($0 + 1), speaker: nil)
        }
        let chunks = MeetingAnalysisPipeline.analysisChunks(turns)
        XCTAssertEqual(chunks[0].last?.id, chunks[1].first?.id)
        XCTAssertTrue(chunks.allSatisfy { Set($0.map(\.id)).count == $0.count })
    }
}
