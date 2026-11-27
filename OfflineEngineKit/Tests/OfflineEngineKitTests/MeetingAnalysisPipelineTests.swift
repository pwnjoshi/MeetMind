import XCTest
@testable import OfflineEngineKit

final class MeetingAnalysisPipelineTests: XCTestCase {
    func testRemoteAudioIsRejectedBeforeAnyEngineStartsAndLeaseIsReleased() async {
        let pipeline = MeetingAnalysisPipeline()
        for _ in 0..<2 {
            do {
                _ = try await pipeline.run(meetingID: UUID(), audio: URL(string: "https://example.com/private.m4a")!,
                    meetingDate: Date(), timezone: "Asia/Kolkata") { _ in XCTFail("No stage should start") }
                XCTFail("Remote audio must be rejected")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("saved on this iPhone"))
            }
        }
    }

    func testQuestionBudgetRejectsOversizedInputBeforeLoadingModel() async {
        do {
            _ = try await MeetingAnalysisPipeline().answer(question: String(repeating: "q", count: 301),
                turns: [AnalysisTurn(id: "t1", text: "Hello", start: 0, end: 1, speaker: nil)])
            XCTFail("Oversized question must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("short question")) }
    }

    func testCaptionDisagreementRecognizesLocalOmissionsAndAdditions() {
        let words = ["we", "approved", "the", "proposal", "today"]
        let alternate = ["we", "did", "not", "approve", "the", "proposal", "today"]
        XCTAssertTrue(MeetingAnalysisPipeline.isCaptionDisagreement(words, alternate))
        XCTAssertTrue(MeetingAnalysisPipeline.isCaptionDisagreement(alternate, words))
        XCTAssertFalse(MeetingAnalysisPipeline.isCaptionDisagreement(words, words))
        XCTAssertFalse(MeetingAnalysisPipeline.isCaptionDisagreement(words, ["we", "sent", "it", "today"]))
    }

    func testCaptionRecoveryRequiresUncoveredAudioInsideTheRecording() {
        let caption = AnalysisTurn(id: "live", text: "Review the draft", start: 4, end: 7, speaker: nil)
        let existing = AnalysisTurn(id: "saved", text: "Review", start: 3, end: 5, speaker: nil)
        XCTAssertTrue(MeetingAnalysisPipeline.isUncoveredCaption(caption, in: [], duration: 8))
        XCTAssertFalse(MeetingAnalysisPipeline.isUncoveredCaption(caption, in: [existing], duration: 8))
        XCTAssertFalse(MeetingAnalysisPipeline.isUncoveredCaption(caption, in: [], duration: 6))
    }

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

    func testAOneSecondReplyKeepsItsOwnSpeaker() {
        let spans = [
            SpeakerSpan(speaker: "S0", start: 0, end: 22),
            SpeakerSpan(speaker: "S1", start: 22, end: 23),
            SpeakerSpan(speaker: "S0", start: 23, end: 30)
        ]
        let turns = [
            AnalysisTurn(id: "t1", text: "Can you take this?", start: 19, end: 22, speaker: nil),
            AnalysisTurn(id: "t2", text: "Yes, I can.", start: 22, end: 23, speaker: nil),
            AnalysisTurn(id: "t3", text: "Thank you.", start: 23, end: 25, speaker: nil)
        ]
        let assigned = MeetingAnalysisPipeline.assignSpeakers(turns: turns, spans: spans)
        XCTAssertEqual(assigned.compactMap(\.speaker), ["S0", "S1", "S0"])
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
    func testHindiJSONInputBudgetIncludesMetadataAndUnicodeBytes() throws {
        let turns = (0..<80).map {
            AnalysisTurn(id: "t\($0)", text: "कल तक भेज देना।", start: Double($0), end: Double($0 + 1), speaker: "Speaker 1")
        }
        for chunk in MeetingAnalysisPipeline.analysisChunks(turns) {
            XCTAssertLessThanOrEqual(try JSONEncoder().encode(chunk).count, 1800)
        }
    }

}
