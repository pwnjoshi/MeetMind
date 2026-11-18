import Foundation

protocol ModelDownloadTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> (URL, HTTPURLResponse)
}

final class SessionModelTransport: ModelDownloadTransport, @unchecked Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }
    deinit { session.invalidateAndCancel() }
    func fetch(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        let (url, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: url)
            throw OfflineError.unavailable("Model server returned an invalid response.")
        }
        return (url, response)
    }
}

/// Bounded HTTP ranges avoid restarting multi-GB transfers after a dropped
/// connection. Only completed, validated ranges are appended to private storage.
struct ResumableModelDownloader: Sendable {
    let transport: any ModelDownloadTransport
    var chunkBytes: Int64 = 33_554_432
    var retryDelayNanoseconds: UInt64 = 1_000_000_000

    func download(_ asset: ModelAsset, to partial: URL,
                  progress: @Sendable (Int64) -> Void) async throws {
        guard chunkBytes > 0, asset.bytes > 0 else { throw OfflineError.unavailable("Invalid model download size.") }
        if !FileManager.default.fileExists(atPath: partial.path) {
            var attributes: [FileAttributeKey: Any] = [:]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: attributes) else {
                throw OfflineError.unavailable("Unable to create model download file.")
            }
        }
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }
        var offset = Int64(try output.seekToEnd())
        guard offset <= asset.bytes else {
            try output.truncate(atOffset: 0)
            throw OfflineError.unavailable("Incomplete model file has an invalid size. Retry the download.")
        }
        progress(offset)
        while offset < asset.bytes {
            try Task.checkCancellation()
            let end = min(asset.bytes - 1, offset + chunkBytes - 1)
            var request = URLRequest(url: asset.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            var lastError: Error?
            var succeeded = false
            for attempt in 0..<3 {
                try Task.checkCancellation()
                do {
                    let (temporary, response) = try await transport.fetch(request)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let range = "bytes \(offset)-\(end)/\(asset.bytes)"
                    let validPartial = response.statusCode == 206 && response.value(forHTTPHeaderField: "Content-Range") == range
                    let validWhole = response.statusCode == 200 && offset == 0 && end == asset.bytes - 1
                    let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value
                    guard (validPartial || validWhole), size == end - offset + 1 else {
                        throw OfflineError.unavailable("Model server returned an incomplete or unexpected byte range. Retry the download.")
                    }
                    try Task.checkCancellation()
                    let input = try FileHandle(forReadingFrom: temporary)
                    defer { try? input.close() }
                    do {
                        while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty {
                            try output.write(contentsOf: bytes)
                        }
                        try output.synchronize()
                    } catch {
                        // Keep the persistent resume boundary consistent if disk
                        // writes fail part-way through a validated range.
                        try output.truncate(atOffset: UInt64(offset))
                        try output.seek(toOffset: UInt64(offset))
                        throw error
                    }
                    offset = end + 1
                    progress(offset)
                    succeeded = true
                    break
                } catch is CancellationError { throw CancellationError() }
                catch {
                    lastError = error
                    if attempt < 2 { try await Task.sleep(nanoseconds: retryDelayNanoseconds * UInt64(attempt + 1)) }
                }
            }
            guard succeeded else { throw lastError ?? OfflineError.unavailable("Model download failed. Retry to resume.") }
        }
    }
}
