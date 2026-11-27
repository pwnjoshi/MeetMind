import Foundation
import OSLog

public enum RecordingTakeState: String, Codable, CaseIterable, Sendable {
    case starting
    case recording
    case stopping
    case validated
    case persisted
}

public struct RecordingTakeJournal: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var id: UUID { meetingID }
    public let version: Int
    public let meetingID: UUID
    public var relativeAudioPath: String
    public let startedAt: Date
    public var lastKnownDuration: TimeInterval
    public var updatedAt: Date
    public var state: RecordingTakeState
    public var failureCode: String?

    public init(
        version: Int = RecordingTakeJournal.currentVersion,
        meetingID: UUID,
        relativeAudioPath: String,
        startedAt: Date,
        lastKnownDuration: TimeInterval = 0,
        updatedAt: Date,
        state: RecordingTakeState,
        failureCode: String? = nil
    ) {
        self.version = version
        self.meetingID = meetingID
        self.relativeAudioPath = relativeAudioPath
        self.startedAt = startedAt
        self.lastKnownDuration = lastKnownDuration
        self.updatedAt = updatedAt
        self.state = state
        self.failureCode = failureCode
    }
}

public enum RecordingRecoveryError: LocalizedError, Sendable, Equatable {
    case unsafeAudioLocation
    case corruptJournal
    case unsupportedJournalVersion(Int)
    case invalidStateTransition(from: RecordingTakeState, to: RecordingTakeState)
    case recoveryRequired

    public var errorDescription: String? {
        switch self {
        case .unsafeAudioLocation:
            return "The recording location is outside Manent's protected recording folder."
        case .corruptJournal:
            return "A recording recovery record is unreadable. It was preserved for support."
        case .unsupportedJournalVersion:
            return "A recording recovery record was written by an unsupported app version."
        case .invalidStateTransition(let from, let to):
            return "The recording recovery state cannot move from \(from.rawValue) to \(to.rawValue)."
        case .recoveryRequired:
            return "An interrupted recording needs attention before another recording can start."
        }
    }
}

@MainActor
public final class RecordingTakeJournalStore {
    public let documentsRoot: URL
    public let recoveryRoot: URL

    private let fileManager: FileManager
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.meetmind.app", category: "RecordingRecovery")

    public init(
        documentsRoot: URL,
        recoveryRoot: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.documentsRoot = documentsRoot.standardizedFileURL
        self.recoveryRoot = recoveryRoot.standardizedFileURL
        self.fileManager = fileManager
        self.now = now
    }

    public static func live(fileManager: FileManager = .default) -> RecordingTakeJournalStore {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return RecordingTakeJournalStore(
            documentsRoot: documents,
            recoveryRoot: support.appendingPathComponent("Manent/RecordingRecovery", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func journalURL(for meetingID: UUID) -> URL {
        recoveryRoot.appendingPathComponent("\(meetingID.uuidString).json")
    }

    public func relativeAudioPath(for audioURL: URL) throws -> String {
        let root = documentsRoot.standardizedFileURL.path
        let candidate = audioURL.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate.hasPrefix(prefix) else { throw RecordingRecoveryError.unsafeAudioLocation }
        let relative = String(candidate.dropFirst(prefix.count))
        guard isSafeRelativePath(relative) else { throw RecordingRecoveryError.unsafeAudioLocation }
        return relative
    }

    /// Resolves against the current Documents container. This deliberately ignores
    /// any sandbox container path from the process that created the journal.
    public func audioURL(for journal: RecordingTakeJournal) throws -> URL {
        guard isSafeRelativePath(journal.relativeAudioPath) else {
            throw RecordingRecoveryError.unsafeAudioLocation
        }
        let root = documentsRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(journal.relativeAudioPath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw RecordingRecoveryError.unsafeAudioLocation
        }
        return candidate
    }

    @discardableResult
    public func createBeforeRecording(meetingID: UUID, audioURL: URL) throws -> RecordingTakeJournal {
        let timestamp = now()
        let journal = RecordingTakeJournal(
            meetingID: meetingID,
            relativeAudioPath: try relativeAudioPath(for: audioURL),
            startedAt: timestamp,
            updatedAt: timestamp,
            state: .starting
        )
        try write(journal)
        return journal
    }

    public func load(meetingID: UUID) throws -> RecordingTakeJournal? {
        let url = journalURL(for: meetingID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(at: url, expectedMeetingID: meetingID)
    }

    public func loadAll() throws -> [RecordingTakeJournal] {
        guard fileManager.fileExists(atPath: recoveryRoot.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        return try urls.map { try decode(at: $0, expectedMeetingID: nil) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    @discardableResult
    public func transition(
        meetingID: UUID,
        to state: RecordingTakeState,
        duration: TimeInterval? = nil,
        failureCode: String? = nil
    ) throws -> RecordingTakeJournal {
        guard var journal = try load(meetingID: meetingID) else {
            throw RecordingRecoveryError.corruptJournal
        }
        guard canTransition(from: journal.state, to: state) else {
            throw RecordingRecoveryError.invalidStateTransition(from: journal.state, to: state)
        }
        journal.state = state
        if let duration, duration.isFinite {
            journal.lastKnownDuration = max(0, duration)
        }
        journal.updatedAt = now()
        journal.failureCode = failureCode
        try write(journal)
        return journal
    }

    /// Duration updates use the UI clock and are intentionally throttled away
    /// from the real-time audio callback.
    @discardableResult
    public func updateDurationIfNeeded(
        meetingID: UUID,
        duration: TimeInterval,
        minimumInterval: TimeInterval = 5
    ) throws -> Bool {
        guard duration.isFinite, var journal = try load(meetingID: meetingID) else { return false }
        let timestamp = now()
        guard timestamp.timeIntervalSince(journal.updatedAt) >= minimumInterval else { return false }
        journal.lastKnownDuration = max(0, duration)
        journal.updatedAt = timestamp
        try write(journal)
        return true
    }

    public func recordFailure(
        meetingID: UUID,
        code: String,
        relativeAudioPath: String? = nil
    ) throws {
        guard var journal = try load(meetingID: meetingID) else { return }
        if let relativeAudioPath {
            guard isSafeRelativePath(relativeAudioPath) else {
                throw RecordingRecoveryError.unsafeAudioLocation
            }
            journal.relativeAudioPath = relativeAudioPath
        }
        journal.failureCode = code
        journal.updatedAt = now()
        try write(journal)
    }

    public func remove(meetingID: UUID) throws {
        let url = journalURL(for: meetingID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: recoveryRoot.path) else { return }
        try fileManager.removeItem(at: recoveryRoot)
    }

    /// Blocks a new writer whenever an older take or journal exists. Invalid
    /// audio is moved, never deleted, and its journal records a content-free code.
    public func assertDestinationAvailable(meetingID: UUID, audioURL: URL) throws {
        if let journal = try load(meetingID: meetingID) {
            try inspectExisting(journal: journal)
            throw RecordingRecoveryError.recoveryRequired
        }
        guard fileManager.fileExists(atPath: audioURL.path) else { return }
        let journal = try createBeforeRecording(meetingID: meetingID, audioURL: audioURL)
        try inspectExisting(journal: journal)
        throw RecordingRecoveryError.recoveryRequired
    }

    @discardableResult
    public func quarantineInvalidAudio(
        for journal: RecordingTakeJournal,
        validationCode: String
    ) throws -> URL? {
        let source = try audioURL(for: journal)
        guard fileManager.fileExists(atPath: source.path) else {
            try recordFailure(meetingID: journal.meetingID, code: "audio_missing")
            return nil
        }
        if journal.relativeAudioPath.hasPrefix("Recordings/Quarantine/") {
            try recordFailure(meetingID: journal.meetingID, code: validationCode)
            return source
        }
        let directory = documentsRoot.appendingPathComponent("Recordings/Quarantine", isDirectory: true)
        try createProtectedDirectory(directory)
        let destination = directory.appendingPathComponent(
            "recovery_\(journal.meetingID.uuidString)_\(UUID().uuidString).\(source.pathExtension.isEmpty ? "audio" : source.pathExtension)"
        )
        try fileManager.moveItem(at: source, to: destination)
        let relative = try relativeAudioPath(for: destination)
        try recordFailure(meetingID: journal.meetingID, code: validationCode, relativeAudioPath: relative)
        let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        logger.error("Invalid interrupted recording quarantined; bytes=\(bytes, privacy: .public)")
        return destination
    }

    public func deleteAudioAndJournal(_ journal: RecordingTakeJournal) throws {
        let audioURL = try audioURL(for: journal)
        if fileManager.fileExists(atPath: audioURL.path) {
            try fileManager.removeItem(at: audioURL)
        }
        try remove(meetingID: journal.meetingID)
    }

    private func inspectExisting(journal: RecordingTakeJournal) throws {
        let audioURL = try audioURL(for: journal)
        guard fileManager.fileExists(atPath: audioURL.path) else {
            try recordFailure(meetingID: journal.meetingID, code: "audio_missing")
            return
        }
        do {
            let info = try CanonicalRecordingValidator.validate(audioURL, fileManager: fileManager)
            if journal.state == .persisted {
                try recordFailure(meetingID: journal.meetingID, code: "destination_already_exists")
            } else {
                _ = try transition(meetingID: journal.meetingID, to: .validated, duration: info.duration,
                                   failureCode: "destination_already_exists")
            }
            logger.notice("Existing recording blocked a writer; duration=\(info.duration, privacy: .public)")
        } catch {
            try quarantineInvalidAudio(for: journal, validationCode: validationCode(for: error))
        }
    }

    private func decode(at url: URL, expectedMeetingID: UUID?) throws -> RecordingTakeJournal {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let journal = try decoder.decode(RecordingTakeJournal.self, from: Data(contentsOf: url))
            guard journal.version == RecordingTakeJournal.currentVersion else {
                throw RecordingRecoveryError.unsupportedJournalVersion(journal.version)
            }
            guard expectedMeetingID == nil || journal.meetingID == expectedMeetingID,
                  isSafeRelativePath(journal.relativeAudioPath) else {
                throw RecordingRecoveryError.corruptJournal
            }
            return journal
        } catch let error as RecordingRecoveryError {
            throw error
        } catch {
            throw RecordingRecoveryError.corruptJournal
        }
    }

    private func write(_ journal: RecordingTakeJournal) throws {
        try createProtectedDirectory(recoveryRoot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(journal)
        try data.write(
            to: journalURL(for: journal.meetingID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func createProtectedDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    private func canTransition(from: RecordingTakeState, to: RecordingTakeState) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.starting, .recording), (.starting, .stopping), (.starting, .validated),
             (.recording, .stopping), (.recording, .validated),
             (.stopping, .validated), (.validated, .persisted):
            return true
        default:
            return false
        }
    }

    private func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("\\") else { return false }
        let components = value.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        return !components.isEmpty && !components.contains("..") && !components.contains(".")
    }

    private func validationCode(for error: Error) -> String {
        switch error as? CanonicalRecordingValidationError {
        case .fileMissing: return "audio_missing"
        case .unreadableAudio: return "audio_unreadable"
        case .emptyAudio: return "audio_empty"
        case .invalidDuration: return "audio_duration_invalid"
        case nil: return "audio_invalid"
        }
    }
}
