import CryptoKit
import Foundation
import os

public struct ModelAsset: Codable, Sendable, Equatable {
    public let path: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64

    public init(path: String, url: URL, sha256: String, bytes: Int64) {
        self.path = path
        self.url = url
        self.sha256 = sha256
        self.bytes = bytes
    }
}

public struct ModelProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let revision: String
    public let files: [ModelAsset]
    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    public init(id: String, name: String, revision: String, files: [ModelAsset]) {
        self.id = id
        self.name = name
        self.revision = revision
        self.files = files
    }
}

/// A fully checked model state. `ready` always means every manifest asset was
/// hashed successfully, either during this call or against unchanged immutable
/// file metadata cached in this process.
public enum ModelReadiness: Codable, Sendable, Equatable {
    case absent
    case downloading(progress: Double)
    case verifying
    case ready
    case corrupt(reason: String)
    case incompatible(reason: String)
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
    private struct AssetMetadata: Hashable {
        let path: String
        let bytes: Int64
        let modifiedAt: TimeInterval
        let fileIdentifier: String
    }

    private var installingModelIDs: Set<String> = []
    private var verificationCache: [String: [AssetMetadata]] = [:]
    private let rootOverride: URL?

    public static let shared: OfflineModelStore = {
        let store = OfflineModelStore()
        // The retired 4B download is 2.5 GB. Delete it once in the background; the app no longer offers it.
        Task.detached(priority: .utility) { await store.removeRetiredModelsOnce() }
        return store
    }()

    /// A root override keeps model lifecycle tests local and deterministic.
    public init(rootDirectory: URL? = nil) {
        self.rootOverride = rootDirectory
    }

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

    private func modelsRoot() throws -> URL {
        if let rootOverride {
            try FileManager.default.createDirectory(at: rootOverride, withIntermediateDirectories: true)
            return rootOverride
        }
        return try Self.privateDirectory("Models")
    }

    private func profileDigest(_ profile: ModelProfile) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(profile)).map { String(format: "%02x", $0) }.joined()
    }

    private func directory(_ profile: ModelProfile) throws -> URL {
        guard !profile.id.isEmpty, profile.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }),
              profile.id != ".", profile.id != ".." else {
            throw OfflineError.unavailable("Invalid model identifier.")
        }
        let digest = try profileDigest(profile)
        return try modelsRoot().appendingPathComponent("\(profile.id)-\(digest.prefix(12))")
    }

    /// Exposed for diagnostics and local fixtures. Callers must still use
    /// `readiness` or `verifiedFolder` before loading any asset.
    public func directoryURL(for profile: ModelProfile) throws -> URL {
        try directory(profile)
    }

    private func validateAsset(_ asset: ModelAsset) throws {
        guard !asset.path.isEmpty, !asset.path.contains(".."), !asset.path.hasPrefix("/"),
              asset.url.scheme == "https", asset.url.host == "huggingface.co" else {
            throw OfflineError.unavailable("Invalid model manifest path or origin.")
        }
    }

    private func metadata(for profile: ModelProfile, in root: URL) throws -> [AssetMetadata] {
        try profile.files.map { asset in
            try validateAsset(asset)
            let url = root.appendingPathComponent(asset.path)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize, Int64(size) == asset.bytes,
                  let modified = values.contentModificationDate,
                  let identifier = values.fileResourceIdentifier else {
                throw OfflineError.unavailable("A required model file is missing or has the wrong size.")
            }
            return AssetMetadata(path: asset.path, bytes: Int64(size), modifiedAt: modified.timeIntervalSinceReferenceDate,
                                 fileIdentifier: String(describing: identifier))
        }
    }

    /// Returns a truthful state by validating the marker, immutable metadata,
    /// and every SHA-256 digest. Successful hashes are reused only while all
    /// metadata for that exact profile revision remains unchanged.
    public func readiness(_ profile: ModelProfile) -> ModelReadiness {
        do {
            let root = try directory(profile)
            let marker = root.appendingPathComponent("verified.json")
            guard FileManager.default.fileExists(atPath: root.path),
                  FileManager.default.fileExists(atPath: marker.path) else { return .absent }
            let installed: ModelProfile
            do {
                installed = try JSONDecoder().decode(ModelProfile.self, from: Data(contentsOf: marker))
            } catch {
                return .corrupt(reason: "The verification marker is unreadable.")
            }
            guard try profileDigest(installed) == profileDigest(profile) else {
                return .incompatible(reason: "The installed model revision does not match this app.")
            }
            let cacheKey = "\(profile.id)|\(profile.revision)|\(try profileDigest(profile))"
            let currentMetadata: [AssetMetadata]
            do {
                currentMetadata = try metadata(for: profile, in: root)
            } catch {
                return .corrupt(reason: "A required model file is missing or has the wrong size.")
            }
            if verificationCache[cacheKey] == currentMetadata { return .ready }
            for asset in profile.files {
                guard try hash(root.appendingPathComponent(asset.path)) == asset.sha256.lowercased() else {
                    verificationCache.removeValue(forKey: cacheKey)
                    return .corrupt(reason: "A model file failed its integrity check.")
                }
            }
            verificationCache[cacheKey] = currentMetadata
            return .ready
        } catch is CancellationError {
            return .verifying
        } catch {
            return .corrupt(reason: "The model could not be verified.")
        }
    }

    /// Kept for compatibility. This now performs full verification rather than
    /// trusting the presence of a marker file.
    public func isInstalled(_ profile: ModelProfile) -> Bool {
        readiness(profile) == .ready
    }

    /// Deletes downloads of models the app no longer offers (matched by the `<id>-<digest>` folder name,
    /// including partial `.download` folders). Returns the removed folder names. Missing folders are fine.
    @discardableResult
    public func removeRetiredModels(ids: [String]) -> [String] {
        guard !ids.isEmpty, let root = try? modelsRoot(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        var removed: [String] = []
        for name in names where ids.contains(where: { name.hasPrefix($0 + "-") }) {
            do {
                try FileManager.default.removeItem(at: root.appendingPathComponent(name))
                removed.append(name)
            } catch {
                Self.retiredLog.error("Could not remove a retired model folder.")
            }
        }
        verificationCache = verificationCache.filter { entry in !ids.contains { entry.key.hasPrefix($0 + "|") } }
        return removed
    }

    private static let retiredLog = os.Logger(subsystem: "OfflineEngineKit", category: "models")
    private static let retiredCleanupKey = "Manent.retiredModelsRemoved.v1"

    /// One-time cleanup at first launch after the update: frees the space of the removed 4B model.
    func removeRetiredModelsOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.retiredCleanupKey) else { return }
        let removed = removeRetiredModels(ids: VidurModel.retiredModelIDs)
        Self.retiredLog.notice("Removed \(removed.count) retired model folder(s) to free storage.")
        defaults.set(true, forKey: Self.retiredCleanupKey)
    }

    public func remove(_ profile: ModelProfile) throws {
        let root = try directory(profile)
        for path in [root, root.appendingPathExtension("download")] {
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
        verificationCache = verificationCache.filter { !$0.key.hasPrefix(profile.id + "|") }
    }

    func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { return false }
            hash.update(data: bytes)
            return true
        }) { }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func verifiedFolder(_ profile: ModelProfile) throws -> URL {
        let state = readiness(profile)
        switch state {
        case .ready:
            return try directory(profile)
        case .absent:
            throw OfflineError.unavailable("Download \(profile.name) first.")
        case .corrupt:
            throw OfflineError.unavailable("\(profile.name) is damaged. Repair Models, then retry.")
        case .incompatible:
            throw OfflineError.unavailable("\(profile.name) is from an incompatible revision. Repair Models, then retry.")
        case .downloading, .verifying:
            throw OfflineError.unavailable("\(profile.name) is not ready yet.")
        }
    }

    public func install(_ profile: ModelProfile, progress: @Sendable @escaping (Double) -> Void) async throws {
        while installingModelIDs.contains(profile.id) {
            try await Task.sleep(for: .milliseconds(250))
        }
        try Task.checkCancellation()
        installingModelIDs.insert(profile.id)
        defer { installingModelIDs.remove(profile.id) }
        if readiness(profile) == .ready {
            progress(1)
            return
        }
        let root = try directory(profile)
        let staging = root.appendingPathExtension("download")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let available = try staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        var pending: Int64 = 0
        var cached: Set<String> = []
        for asset in profile.files {
            try validateAsset(asset)
            let partial = staging.appendingPathComponent(asset.path).appendingPathExtension("partial")
            if (try? hash(staging.appendingPathComponent(asset.path))) == asset.sha256.lowercased() {
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
            try validateAsset(asset)
            let target = staging.appendingPathComponent(asset.path)
            if !cached.contains(asset.path) {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let offset = complete, total = max(1, profile.downloadBytes)
                let download = target.appendingPathExtension("partial")
                let downloader = ResumableModelDownloader(transport: SessionModelTransport())
                try await downloader.download(asset, to: download) { written in
                    progress(min(1, Double(offset + written) / Double(total)))
                }
                guard try hash(download) == asset.sha256.lowercased() else {
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
        try finishInstallation(profile, staging: staging, root: root)
    }

    /// Repairs a damaged installation without exposing an unverified folder.
    /// The old folder stays in place until a complete replacement is verified.
    public func repair(_ profile: ModelProfile, progress: @Sendable @escaping (Double) -> Void) async throws {
        verificationCache = verificationCache.filter { !$0.key.hasPrefix(profile.id + "|") }
        try await install(profile, progress: progress)
    }

    /// Installs a local, already downloaded fixture or managed package. Every
    /// file is copied to staging and hashed before the atomic directory swap.
    /// This is also the deterministic repair seam used by model lifecycle tests.
    public func repair(_ profile: ModelProfile, fromVerifiedDirectory source: URL) throws {
        let root = try directory(profile)
        let staging = root.appendingPathExtension("download")
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for asset in profile.files {
                try validateAsset(asset)
                let sourceFile = source.appendingPathComponent(asset.path)
                let target = staging.appendingPathComponent(asset.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: sourceFile, to: target)
                guard try hash(target) == asset.sha256.lowercased(),
                      Int64((try target.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? -1) == asset.bytes else {
                    throw OfflineError.unavailable("The replacement for \(profile.name) failed verification.")
                }
            }
            try finishInstallation(profile, staging: staging, root: root)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func finishInstallation(_ profile: ModelProfile, staging: URL, root: URL) throws {
        try JSONEncoder().encode(profile).write(to: staging.appendingPathComponent("verified.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Verify staging independently before replacing the current installation.
        for asset in profile.files {
            guard try hash(staging.appendingPathComponent(asset.path)) == asset.sha256.lowercased() else {
                throw OfflineError.unavailable("The replacement for \(profile.name) failed verification.")
            }
        }
        if FileManager.default.fileExists(atPath: root.path) {
            _ = try FileManager.default.replaceItemAt(root, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: root)
        }
        verificationCache = verificationCache.filter { !$0.key.hasPrefix(profile.id + "|") }
        guard readiness(profile) == .ready else {
            throw OfflineError.unavailable("\(profile.name) could not be verified after installation.")
        }
    }
}
