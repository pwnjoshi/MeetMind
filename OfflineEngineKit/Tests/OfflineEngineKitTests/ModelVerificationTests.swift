import XCTest
import CryptoKit
@testable import OfflineEngineKit

final class ModelVerificationTests: XCTestCase {
    func testStreamingVerificationIncludesEveryChunkAndFinalPartialRead() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let writer = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x5a, count: 1_048_576)
        for _ in 0..<33 { try writer.write(contentsOf: chunk) }
        try writer.write(contentsOf: Data("end".utf8))
        try writer.close()
        let digest = try await OfflineModelStore().hash(url)
        XCTAssertEqual(digest, "c9d2946116c721ee1626fc172c4be882ea16a16420d4a04db8317d10b4d54db5")
    }

    func testAlreadyCancelledVerificationDoesNotContinueReadingModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 2_097_152).write(to: url)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OfflineModelStore().hash(url)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled verification must stop before reading more model data")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCorruptModelIsNamedAndLocalRepairRestoresReadyState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let valid = Data("model-bytes".utf8)
        let digest = SHA256.hash(data: valid).map { String(format: "%02x", $0) }.joined()
        try valid.write(to: source.appendingPathComponent("weights.bin"))
        let profile = ModelProfile(id: "fixture-model", name: "Fixture Model", revision: "r1", files: [
            ModelAsset(path: "weights.bin", url: URL(string: "https://huggingface.co/example/weights.bin")!,
                       sha256: digest, bytes: Int64(valid.count))
        ])
        let store = OfflineModelStore(rootDirectory: root.appendingPathComponent("models"))
        try await store.repair(profile, fromVerifiedDirectory: source)
        let initiallyReady = await store.readiness(profile)
        XCTAssertEqual(initiallyReady, .ready)

        let installedRoot = try await store.directoryURL(for: profile)
        let installed = installedRoot.appendingPathComponent("weights.bin")
        try Data("broken-byte".utf8).write(to: installed)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: installed.path)
        let corrupt = await store.readiness(profile)
        guard case .corrupt(let reason) = corrupt else {
            return XCTFail("Expected corrupt readiness, got \(corrupt)")
        }
        XCTAssertFalse(reason.isEmpty)

        try await store.repair(profile, fromVerifiedDirectory: source)
        let repaired = await store.readiness(profile)
        XCTAssertEqual(repaired, .ready)
    }
}
