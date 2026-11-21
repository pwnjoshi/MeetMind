import Foundation

/// One saved recording file on this iPhone.
public struct LocalRecordingFile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let date: Date
    public let duration: TimeInterval
    public let bytes: Int64
    public let url: URL

    public init(id: UUID, title: String, date: Date, duration: TimeInterval, bytes: Int64, url: URL) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.bytes = bytes
        self.url = url
    }
}

/// Size and cleanup helpers for recording files stored by the app.
public enum LocalRecordingStorage {
    public static let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "caf", "aac", "aiff", "aif", "mp4"]

    public static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    public static func totalBytes(_ files: [LocalRecordingFile]) -> Int64 {
        files.reduce(Int64(0)) { $0 + max($1.bytes, 0) }
    }

    public static func newestFirst(_ files: [LocalRecordingFile]) -> [LocalRecordingFile] {
        files.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    public static func formatted(duration: TimeInterval) -> String {
        let total = Int(max(duration, 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Deletes audio files below `root`. Returns how many files and bytes were removed.
    @discardableResult
    public static func removeAudioFiles(under root: URL, fileManager: FileManager = .default) -> (files: Int, bytes: Int64) {
        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return (0, 0) }
        var targets: [URL] = []
        while let next = enumerator.nextObject() as? URL {
            if audioExtensions.contains(next.pathExtension.lowercased()) { targets.append(next) }
        }
        var files = 0
        var bytes: Int64 = 0
        for url in targets {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let size = fileSize(at: url, fileManager: fileManager)
            if (try? fileManager.removeItem(at: url)) != nil {
                files += 1
                bytes += size
            }
        }
        return (files, bytes)
    }
}
