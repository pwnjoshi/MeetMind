import Foundation
import OfflineEngineKit

/// What the voice-naming step learned about one meeting: the voice embedding of each detected label
/// and who it was matched to. Embeddings only, no audio.
public struct MeetingVoiceRecord: Codable, Equatable, Sendable {
    /// Diarization model revision that produced the embeddings.
    public var modelRevision: String
    public var centroids: [String: [Float]]
    public var speechSeconds: [String: Double]
    public var matches: [String: VoiceMatch]
    /// Labels already folded into a person's profile, so one voice is never learned twice.
    public var learned: [String: UUID]

    public init(modelRevision: String, centroids: [String: [Float]], speechSeconds: [String: Double],
                matches: [String: VoiceMatch] = [:], learned: [String: UUID] = [:]) {
        self.modelRevision = modelRevision
        self.centroids = centroids
        self.speechSeconds = speechSeconds
        self.matches = matches
        self.learned = learned
    }
}

/// On-device store of voice profiles (per person) and per-meeting match records.
///
/// The file lives in Application Support, is excluded from backup and protected until first unlock.
/// Profiles are valid for one diarization model revision; learning under another revision starts over.
public final class VoiceProfileStore: @unchecked Sendable {
    public static let shared = VoiceProfileStore()
    static let formatVersion = 1

    private struct Snapshot: Codable, Equatable {
        var version = VoiceProfileStore.formatVersion
        var modelRevision: String?
        var profiles: [String: VoiceProfile] = [:]
        var meetings: [String: MeetingVoiceRecord] = [:]
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var snapshot = Snapshot()

    public static func storeURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent("Manent/VoiceProfiles/voice-profiles-v1.json")
    }

    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { storeURL(applicationSupportRoot: $0) }
    }

    /// Pass `nil` for an in-memory store (used by tests).
    public init(fileURL: URL? = VoiceProfileStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Snapshot.self, from: data),
           stored.version == Self.formatVersion {
            snapshot = stored
        }
    }

    public var isEmpty: Bool {
        locked { snapshot.profiles.isEmpty && snapshot.meetings.isEmpty }
    }

    // MARK: Profiles

    /// Profiles usable with embeddings from `revision`. Empty when the store was built with another revision.
    public func profiles(revision: String) -> [VoiceProfile] {
        locked { snapshot.modelRevision == revision ? Array(snapshot.profiles.values) : [] }
    }

    public func profile(for personID: UUID, revision: String) -> VoiceProfile? {
        locked {
            guard snapshot.modelRevision == revision else { return nil }
            return snapshot.profiles[personID.uuidString]
        }
    }

    /// Folds one embedding into the person's profile and saves. A different model revision discards
    /// every stored profile first, because embeddings of two model versions cannot be compared.
    @discardableResult
    public func learn(_ embedding: [Float], personID: UUID, revision: String) throws -> VoiceProfile.LearnResult {
        try locked {
            let previous = snapshot
            if snapshot.modelRevision != revision {
                snapshot.profiles = [:]
                snapshot.modelRevision = revision
            }
            var profile = snapshot.profiles[personID.uuidString] ?? VoiceProfile(personID: personID)
            let result = profile.learn(embedding)
            guard result == .created || result == .updated else {
                snapshot = previous
                return result
            }
            snapshot.profiles[personID.uuidString] = profile
            do { try persist() } catch { snapshot = previous; throw error }
            return result
        }
    }

    // MARK: Meetings

    public func record(for meetingID: UUID) -> MeetingVoiceRecord? {
        locked { snapshot.meetings[meetingID.uuidString] }
    }

    public func setRecord(_ record: MeetingVoiceRecord, for meetingID: UUID) throws {
        try locked {
            let previous = snapshot
            snapshot.meetings[meetingID.uuidString] = record
            do { try persist() } catch { snapshot = previous; throw error }
        }
    }

    public func removeMeeting(_ meetingID: UUID) throws {
        try locked {
            guard snapshot.meetings[meetingID.uuidString] != nil else { return }
            let previous = snapshot
            snapshot.meetings[meetingID.uuidString] = nil
            do { try persist() } catch { snapshot = previous; throw error }
        }
    }

    public func hasMeeting(_ meetingID: UUID) -> Bool {
        locked { snapshot.meetings[meetingID.uuidString] != nil }
    }

    /// Deletes the file and forgets everything in memory.
    public func eraseAll() throws {
        try locked {
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            snapshot = Snapshot()
        }
    }

    // MARK: Persistence

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func persist() throws {
        guard let fileURL else { return }
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
