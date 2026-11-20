import Foundation
import SwiftData

/// Permanently removes everything Manent stores on this iPhone for the user.
/// Downloaded offline model files are kept because they are public files, not user data.
@MainActor
public enum LocalDataEraser {
    public struct ErasureReport: Equatable, Sendable {
        public var meetingsDeleted = 0
        public var audioFilesDeleted = 0
        public var bytesFreed: Int64 = 0
    }

    public static let profileDefaultsKeys = ["MeetMind_UserProfile", "Manent.workspaceName"]

    public static func eraseAll(modelContext: ModelContext,
                                defaults: UserDefaults = .standard,
                                vidurPreferences: VidurPreferences = .shared,
                                fileManager: FileManager = .default) throws -> ErasureReport {
        var summary = ErasureReport()

        let meetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        summary.meetingsDeleted = meetings.count
        var audioURLs: [URL] = []
        for meeting in meetings {
            if let resolved = meeting.resolvedAudioFileURL { audioURLs.append(resolved) }
            if let stored = meeting.audioFileURL, stored.isFileURL { audioURLs.append(stored) }
        }
        var seen = Set<String>()
        for url in audioURLs where seen.insert(url.path).inserted {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let size = LocalRecordingStorage.fileSize(at: url, fileManager: fileManager)
            if (try? fileManager.removeItem(at: url)) != nil {
                summary.audioFilesDeleted += 1
                summary.bytesFreed += size
            }
        }

        for meeting in meetings { modelContext.delete(meeting) }
        try modelContext.save()
        try deleteAll(TranscriptSegment.self, in: modelContext)
        try deleteAll(Summary.self, in: modelContext)
        try deleteAll(ActionItem.self, in: modelContext)
        try deleteAll(Note.self, in: modelContext)
        try deleteAll(Speaker.self, in: modelContext)
        try deleteAll(Tag.self, in: modelContext)
        try deleteAll(Folder.self, in: modelContext)
        try modelContext.save()

        // Remaining recording files the app created (imports, rolling chunks, leftovers).
        var roots: [URL] = [fileManager.temporaryDirectory]
        roots.append(contentsOf: fileManager.urls(for: .documentDirectory, in: .userDomainMask))
        roots.append(contentsOf: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
        for root in roots {
            let removed = LocalRecordingStorage.removeAudioFiles(under: root, fileManager: fileManager)
            summary.audioFilesDeleted += removed.files
            summary.bytesFreed += removed.bytes
        }

        for key in profileDefaultsKeys { defaults.removeObject(forKey: key) }
        LocalInboxReadStore(defaults: defaults).reset()
        vidurPreferences.clearHistory()
        return summary
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let remaining = try context.fetch(FetchDescriptor<T>())
        for object in remaining { context.delete(object) }
    }
}
