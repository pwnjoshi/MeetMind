import CryptoKit
import Foundation

public struct ModelAsset: Codable, Sendable {
    public let path: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
}

public struct ModelProfile: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let revision: String
    public let files: [ModelAsset]
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
}

public enum OfflineError: LocalizedError {
    case unavailable(String)
    case memoryBudget(requiredEstimate: UInt64, budget: UInt64)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .memoryBudget(let required, let available):
            if required > ModelMemoryAdmission.maximumBudget {
                return "This model configuration exceeds the safe memory budget. Your recording and completed steps are preserved."
            }
            let needed = ByteCountFormatter.string(fromByteCount: Int64(clamping: required), countStyle: .memory)
            let free = ByteCountFormatter.string(fromByteCount: Int64(clamping: available), countStyle: .memory)
            return "Not enough memory is available for offline analysis (estimated \(needed), available \(free)). Close other apps and retry. Your recording and completed steps are preserved."
        }
    }
}

/// The only network-capable component. Engines receive verified local paths.
public actor OfflineModelStore {
    public static let shared = OfflineModelStore()
    public static func profiles() throws -> [ModelProfile] {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json") else {
            throw OfflineError.unavailable("Model manifest is missing.")
        }
        return try JSONDecoder().decode([ModelProfile].self, from: Data(contentsOf: url))
    }

    public static var notices: String {
        guard let url = Bundle.module.url(forResource: "notices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Notices unavailable." }
        return text
    }

    public static func privateDirectory(_ name: String) throws -> URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineIntelligence", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        url.appendPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return url
    }

    private func directory(_ profile: ModelProfile) throws -> URL {
        guard !profile.id.isEmpty, profile.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }),
              profile.id != ".", profile.id != ".." else {
            throw OfflineError.unavailable("Invalid model identifier.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(profile.files)).map { String(format: "%02x", $0) }.joined()
        return try Self.privateDirectory("Models").appendingPathComponent("\(profile.id)-\(digest.prefix(12))")
    }

    public func isInstalled(_ profile: ModelProfile) -> Bool {
        guard let root = try? directory(profile) else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("verified.json").path)
    }

    public func remove(_ profile: ModelProfile) throws {
        let root = try directory(profile)
        for path in [root, root.appendingPathExtension("download")] {
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
    }

    func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        // FileHandle can bridge autoreleased NSData. Bound its lifetime to one
        // chunk rather than retaining temporary buffers until a multi-GB hash
        // finishes on the actor's current executor turn.
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { return false }
            hash.update(data: bytes)
            return true
        }) { }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func verifiedFolder(_ profile: ModelProfile) throws -> URL {
        let root = try directory(profile)
        guard isInstalled(profile) else { throw OfflineError.unavailable("Download \(profile.name) first.") }
        for asset in profile.files {
            guard try hash(root.appendingPathComponent(asset.path)) == asset.sha256 else {
                throw OfflineError.unavailable("Model integrity check failed. Download the model again.")
            }
        }
        return root
    }

    public func install(_ profile: ModelProfile, progress: @Sendable @escaping (Double) -> Void) async throws {
        if isInstalled(profile) {
            do {
                _ = try verifiedFolder(profile)
                progress(1)
                return
            } catch is CancellationError { throw CancellationError() }
            catch { /* Replace corrupt installations only after verifying a new copy. */ }
        }
        let root = try directory(profile)
        let staging = root.appendingPathExtension("download")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let available = try staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        var pending: Int64 = 0
        var cached: Set<String> = []
        for asset in profile.files {
            guard !asset.path.contains(".."), !asset.path.hasPrefix("/"),
                  asset.url.scheme == "https", asset.url.host == "huggingface.co" else {
                throw OfflineError.unavailable("Invalid model manifest path or origin.")
            }
            let partial = staging.appendingPathComponent(asset.path).appendingPathExtension("partial")
            if (try? hash(staging.appendingPathComponent(asset.path))) == asset.sha256 {
                cached.insert(asset.path)
                continue
            }
            let resumed = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.int64Value ?? 0
            pending += max(0, asset.bytes - min(asset.bytes, resumed))
        }
        guard available > pending + 500_000_000 else {
            throw OfflineError.unavailable("Not enough storage. Free space for the model plus 500 MB of working space.")
        }
        var complete: Int64 = 0
        for asset in profile.files {
            try Task.checkCancellation()
            guard !asset.path.contains(".."), !asset.path.hasPrefix("/"),
                  asset.url.scheme == "https", asset.url.host == "huggingface.co" else {
                throw OfflineError.unavailable("Invalid model manifest path or origin.")
            }
            let target = staging.appendingPathComponent(asset.path)
            if !cached.contains(asset.path) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let offset = complete, total = max(1, profile.downloadBytes)
                let download = target.appendingPathExtension("partial")
                let downloader = ResumableModelDownloader(transport: SessionModelTransport())
                try await downloader.download(asset, to: download) { written in
                    progress(min(1, Double(offset + written) / Double(total)))
                }
                guard try hash(download) == asset.sha256 else {
                    try? FileManager.default.removeItem(at: download)
                    throw OfflineError.unavailable("Model download failed its integrity check. Retry the download.")
                }
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: download, to: target)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            }
            complete += asset.bytes
            progress(Double(complete) / Double(max(1, profile.downloadBytes)))
        }
        try JSONEncoder().encode(profile).write(to: staging.appendingPathComponent("verified.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if FileManager.default.fileExists(atPath: root.path) {
            _ = try FileManager.default.replaceItemAt(root, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: root)
        }
    }
}
