import XCTest
@testable import OfflineEngineKit

final class MemoryAdmissionTests: XCTestCase {
    func testSmallCandidateFitsMeasuredDeviceBudget() {
        XCTAssertNoThrow(try ModelMemoryAdmission.check(modelBytes: 1_282_439_584, availableBytes: 2_500_000_000))
    }
    func testLargeCandidateIsRejectedBeforeAllocation() {
        XCTAssertThrowsError(try ModelMemoryAdmission.check(modelBytes: 2_497_280_256, availableBytes: 4_000_000_000)) { error in
            guard let offline = error as? OfflineError,
                  case let .memoryBudget(required, budget) = offline else { return XCTFail("Expected memory rejection") }
            XCTAssertEqual(required, 3_247_280_256)
            XCTAssertEqual(budget, 3_000_000_000)
        }
    }
    func testLowAvailableMemoryRejectsEvenSmallCandidate() {
        XCTAssertThrowsError(try ModelMemoryAdmission.check(modelBytes: 1_282_439_584, availableBytes: 1_500_000_000))
    }
    func testOversizedMetadataCannotOverflowAdmissionCheck() {
        XCTAssertThrowsError(try ModelMemoryAdmission.check(modelBytes: UInt64.max, availableBytes: UInt64.max))
    }
}
