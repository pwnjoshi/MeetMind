import XCTest
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
}
