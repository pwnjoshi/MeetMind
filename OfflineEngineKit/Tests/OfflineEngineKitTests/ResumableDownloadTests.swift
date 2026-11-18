import Foundation
import XCTest
@testable import OfflineEngineKit

private actor FixtureTransport: ModelDownloadTransport {
    enum Behavior: Equatable, Sendable { case normal, failFirst, badRange, truncated, cancelled }
    let root: URL
    let behavior: Behavior
    var ranges: [String] = []
    let content = Data("abcdefghij".utf8)
    init(root: URL, behavior: Behavior = .normal) { self.root = root; self.behavior = behavior }
    func fetch(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let range = request.value(forHTTPHeaderField: "Range")!
        ranges.append(range)
        if behavior == .failFirst && ranges.count == 1 { throw URLError(.networkConnectionLost) }
        if behavior == .cancelled { throw CancellationError() }
        let numbers = range.dropFirst("bytes=".count).split(separator: "-").map { Int($0)! }
        let start = numbers[0], end = numbers[1]
        var data = content.subdata(in: start..<(end + 1))
        if behavior == .truncated { data = data.dropLast() }
        let file = root.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        let header = behavior == .badRange ? "bytes 0-0/10" : "bytes \(start)-\(end)/10"
        return (file, HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: ["Content-Range": header])!)
    }
}

@MainActor
final class ResumableDownloadTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private var asset: ModelAsset {
        ModelAsset(path: "model.gguf", url: URL(string: "https://huggingface.co/test/model")!, sha256: String(repeating: "a", count: 64), bytes: 10)
    }

    func testBoundedRangesProduceExactFile() async throws {
        let root = try directory(), output = root.appendingPathComponent("model.partial")
        let transport = FixtureTransport(root: root)
        let downloader = ResumableModelDownloader(transport: transport, chunkBytes: 4, retryDelayNanoseconds: 0)
        try await downloader.download(asset, to: output) { _ in }
        XCTAssertEqual(try Data(contentsOf: output), Data("abcdefghij".utf8))
        let ranges = await transport.ranges
        XCTAssertEqual(ranges, ["bytes=0-3", "bytes=4-7", "bytes=8-9"])
    }

    func testResumesExistingPrefixWithoutRedownloading() async throws {
        let root = try directory(), output = root.appendingPathComponent("model.partial")
        try Data("abc".utf8).write(to: output)
        let transport = FixtureTransport(root: root)
        try await ResumableModelDownloader(transport: transport, chunkBytes: 4, retryDelayNanoseconds: 0)
            .download(asset, to: output) { _ in }
        XCTAssertEqual(try Data(contentsOf: output), Data("abcdefghij".utf8))
        let ranges = await transport.ranges
        XCTAssertEqual(ranges, ["bytes=3-6", "bytes=7-9"])
    }

    func testRetriesNetworkLossAtSameBoundary() async throws {
        let root = try directory(), output = root.appendingPathComponent("model.partial")
        let transport = FixtureTransport(root: root, behavior: .failFirst)
        try await ResumableModelDownloader(transport: transport, chunkBytes: 4, retryDelayNanoseconds: 0)
            .download(asset, to: output) { _ in }
        XCTAssertEqual(try Data(contentsOf: output), Data("abcdefghij".utf8))
        let ranges = await transport.ranges
        XCTAssertEqual(Array(ranges.prefix(2)), ["bytes=0-3", "bytes=0-3"])
    }

    func testBadRangeAndTruncatedResponsesNeverAdvancePrefix() async throws {
        for behavior in [FixtureTransport.Behavior.badRange, .truncated] {
            let root = try directory(), output = root.appendingPathComponent("model.partial")
            let transport = FixtureTransport(root: root, behavior: behavior)
            do {
                try await ResumableModelDownloader(transport: transport, chunkBytes: 4, retryDelayNanoseconds: 0)
                    .download(asset, to: output) { _ in }
                XCTFail("Invalid response must fail")
            } catch {
                XCTAssertEqual(try Data(contentsOf: output).count, 0)
                let ranges = await transport.ranges
                XCTAssertEqual(ranges.count, 3)
            }
        }
    }

    func testCancellationDoesNotRetry() async throws {
        let root = try directory(), output = root.appendingPathComponent("model.partial")
        let transport = FixtureTransport(root: root, behavior: .cancelled)
        do {
            try await ResumableModelDownloader(transport: transport, chunkBytes: 4, retryDelayNanoseconds: 0)
                .download(asset, to: output) { _ in }
            XCTFail("Cancelled transfer must stop")
        } catch is CancellationError {
            let ranges = await transport.ranges
            XCTAssertEqual(ranges.count, 1)
        }
    }
}
