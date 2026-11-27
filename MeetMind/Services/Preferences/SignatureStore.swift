import Foundation

/// Stores the user's handwritten signature as a PNG in Application Support.
/// Local only. Used by the minutes sign-off and PDF export.
public struct SignatureStore: Sendable {
    public static let shared = SignatureStore()

    private let directoryOverride: URL?

    public init(directory: URL? = nil) {
        self.directoryOverride = directory
    }

    private var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Signature", isDirectory: true)
    }

    private var fileURL: URL { directory.appendingPathComponent("signature.png") }

    public var hasSignature: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Returns the PNG data, or nil when no signature is saved.
    public func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    /// Writes the PNG atomically with file protection.
    public func save(pngData: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pngData.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func remove() throws {
        guard hasSignature else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Removes the signature folder. Call from the erase-all coordinator.
    public func eraseAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
