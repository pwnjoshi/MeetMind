import XCTest
import OfflineEngineKit
@testable import MeetMind

final class ModelDownloadUXTests: XCTestCase {
    private func profile(id: String, bytes: Int64) -> ModelProfile {
        ModelProfile(id: id, name: id, revision: "fixture", files: [
            ModelAsset(path: "model.bin", url: URL(string: "https://huggingface.co/fixture/model.bin")!,
                       sha256: String(repeating: "a", count: 64), bytes: bytes)
        ])
    }

    func testByteAggregationWeightsModelsByDownloadSize() {
        let transcript = profile(id: "whisper-large", bytes: 100)
        let minutes = profile(id: "qwen-1.7b", bytes: 300)
        let accumulator = ModelDownloadProgressAccumulator(profiles: [transcript, minutes])

        XCTAssertEqual(accumulator.update(modelID: transcript.id, fraction: 0.5).downloadedBytes, 50)
        XCTAssertEqual(accumulator.update(modelID: transcript.id, fraction: 1).fraction, 0.25, accuracy: 0.0001)
        let secondModel = accumulator.update(modelID: minutes.id, fraction: 0.25)
        XCTAssertEqual(secondModel.downloadedBytes, 175)
        XCTAssertEqual(secondModel.fraction, 0.4375, accuracy: 0.0001)
        XCTAssertEqual(secondModel.currentModelName, "Minutes & Vidur model")
    }

    func testAggregateProgressNeverMovesBackward() {
        let transcript = profile(id: "whisper-large", bytes: 100)
        let speakers = profile(id: "diarization", bytes: 20)
        let accumulator = ModelDownloadProgressAccumulator(profiles: [transcript, speakers])

        let first = accumulator.update(modelID: transcript.id, fraction: 0.8)
        let stale = accumulator.update(modelID: transcript.id, fraction: 0.2)
        let nextModel = accumulator.update(modelID: speakers.id, fraction: 0)

        XCTAssertEqual(stale.downloadedBytes, first.downloadedBytes)
        XCTAssertGreaterThanOrEqual(nextModel.downloadedBytes, stale.downloadedBytes)
        XCTAssertEqual(nextModel.downloadedBytes, 100)
    }

    func testLargeCellularAndExpensiveDownloadsRequireConfirmation() {
        let cellular = ConnectivitySnapshot(kind: .cellular)
        XCTAssertEqual(DownloadAccessPolicy.decision(for: 1_900_000_000, connectivity: cellular), .confirmCellular)
        XCTAssertEqual(DownloadAccessPolicy.decision(for: 50_000_000, connectivity: cellular), .allow)

        let expensiveWiFi = ConnectivitySnapshot(kind: .wifi, isExpensive: true)
        XCTAssertEqual(DownloadAccessPolicy.decision(for: 1_900_000_000, connectivity: expensiveWiFi), .confirmCellular)
    }

    func testUnsatisfiedPathMapsToOfflineAndBlocksDownload() {
        let kind = ConnectivityKind.map(isSatisfied: false, usesWiFi: true)
        XCTAssertEqual(kind, .offline)
        XCTAssertEqual(
            DownloadAccessPolicy.decision(for: 1, connectivity: ConnectivitySnapshot(kind: kind)),
            .offline
        )
    }

    func testStorageShortageCalculationIsExactAndNeverNegative() {
        XCTAssertEqual(ModelStorageCapacity.shortage(required: 2_400_000_000, available: 2_000_000_000), 400_000_000)
        XCTAssertEqual(ModelStorageCapacity.shortage(required: 1_000, available: 2_000), 0)
        let capacity = ModelStorageCapacity(downloadBytes: 1_900_000_000,
                                            requiredFreeBytes: 2_400_000_000,
                                            availableBytes: 2_000_000_000)
        XCTAssertFalse(capacity.hasEnoughSpace)
        XCTAssertEqual(capacity.shortageBytes, 400_000_000)
    }
}
