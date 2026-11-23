import XCTest
@testable import OfflineEngineKit

final class AnalysisContractTests: XCTestCase {
    func testManifestIsPinnedAndHasAllCandidates() throws {
        let profiles = try OfflineModelStore.profiles()
        XCTAssertEqual(Set(profiles.map(\.id)), Set(["whisper-small", "whisper-large", "diarization", "qwen-1.7b"]))
        for profile in profiles {
            XCTAssertFalse(profile.revision.contains("main"))
            XCTAssertGreaterThan(profile.downloadBytes, 0)
            XCTAssertEqual(Set(profile.files.map(\.path)).count, profile.files.count)
            for file in profile.files {
                XCTAssertEqual(file.sha256.count, 64)
                XCTAssertTrue(file.url.absoluteString.contains("/resolve/"))
                XCTAssertFalse(file.path.contains(".."))
            }
        }
    }

    private func result(quote: String, id: String = "t1", category: String = "Follow-up") throws -> LocalAnalysisResult {
        let json: [String: Any] = ["discussion": [], "decisions": [], "tasks": [
            ["title": "Send estimate", "category": category, "owner": NSNull(), "deadlineText": NSNull(), "priority": NSNull(),
             "evidence": [["turnID": id, "quote": quote]]]
        ]]
        return try JSONDecoder().decode(LocalAnalysisResult.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testOriginalHinglishEvidenceAccepted() throws {
        try result(quote: "estimate bhej dena").validate(against: OfflineBenchmarkRunner.syntheticTurns)
    }

    func testTranslatedEvidenceRejected() throws {
        XCTAssertThrowsError(try result(quote: "Send the estimate tomorrow").validate(against: OfflineBenchmarkRunner.syntheticTurns))
    }

    func testUnknownTurnRejected() throws {
        XCTAssertThrowsError(try result(quote: "estimate", id: "missing").validate(against: OfflineBenchmarkRunner.syntheticTurns))
    }

    func testInvalidCategoryRejected() throws {
        XCTAssertThrowsError(try result(quote: "estimate", category: "Finance").validate(against: OfflineBenchmarkRunner.syntheticTurns))
    }

    func testEmptyEvidenceRejected() throws {
        XCTAssertThrowsError(try result(quote: "").validate(against: OfflineBenchmarkRunner.syntheticTurns))
    }

    func testNoTasksAndNoDecisionsAreValid() throws {
        let result = try JSONDecoder().decode(LocalAnalysisResult.self, from: Data(#"{"discussion":[],"decisions":[],"tasks":[]}"#.utf8))
        XCTAssertNoThrow(try result.validate(against: OfflineBenchmarkRunner.syntheticTurns))
    }
}
