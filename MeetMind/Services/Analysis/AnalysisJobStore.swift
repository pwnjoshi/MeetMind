import Foundation
import OfflineEngineKit

public enum AnalysisJobState: String, Codable, Sendable {
    case needsModels
    case downloading
    case verifying
    case queued
    case running
    case paused
    case failed
    case speakerReview
    case completed
}

public enum AnalysisStage: String, Codable, Sendable {
    case preparing
    case transcription
    case speakers
    case analysis
    case saving
    case completed
}

public enum AnalysisExecutionOwner: String, Codable, Sendable {
    case foreground
    case background
}

public enum AnalysisRecoveryAction: String, Codable, Sendable {
    case retry
    case repairModels
    case changeLanguage
    case openTranscript
    case processNow
    case returnToMeetings
}

public enum AnalysisFailureCode: String, Codable, Sendable {
    case jobStoreCorrupt
    case sourceUnavailable
    case sourceChanged
    case audioUnreadable
    case noSpeech
    case modelAbsent
    case modelCorrupt
    case resourceConstrained
    case checkpointCorrupt
    case persistenceFailed
    case processingFailed
    case leaseConflict
    case schedulingFailed
}

public struct AnalysisFailure: Codable, Sendable, Equatable {
    public let code: AnalysisFailureCode
    public let message: String
    public let recoveryAction: AnalysisRecoveryAction
    public let retryable: Bool

    public static func stable(_ code: AnalysisFailureCode, modelName: String? = nil) -> Self {
        switch code {
        case .jobStoreCorrupt:
            return Self(code: code, message: "Analysis status could not be read. Your recording and existing meeting data are preserved.", recoveryAction: .returnToMeetings, retryable: false)
        case .sourceUnavailable:
            return Self(code: code, message: "The saved recording is unavailable. Return to Meetings and choose another recording.", recoveryAction: .returnToMeetings, retryable: false)
        case .sourceChanged:
            return Self(code: code, message: "The saved recording changed after analysis began. Retry to start a new checkpoint.", recoveryAction: .retry, retryable: true)
        case .audioUnreadable:
            return Self(code: code, message: "This recording contains no readable audio. The original file has been preserved.", recoveryAction: .returnToMeetings, retryable: false)
        case .noSpeech:
            return Self(code: code, message: "No speech was recognized. Your recording is preserved. Retry or change the recording language.", recoveryAction: .changeLanguage, retryable: true)
        case .modelAbsent:
            return Self(code: code, message: "Required on-device models are not installed.", recoveryAction: .repairModels, retryable: true)
        case .modelCorrupt:
            let name = modelName ?? "A required model"
            return Self(code: code, message: "\(name) is damaged and must be repaired before processing can continue.", recoveryAction: .repairModels, retryable: true)
        case .resourceConstrained:
            return Self(code: code, message: "This iPhone cannot safely run analysis right now. Close other apps, let the phone cool, and retry.", recoveryAction: .retry, retryable: true)
        case .checkpointCorrupt:
            return Self(code: code, message: "The saved analysis checkpoint is invalid. Retry from the preserved recording or open the saved transcript.", recoveryAction: .openTranscript, retryable: true)
        case .persistenceFailed:
            return Self(code: code, message: "Completed analysis could not be saved. Your recording and transcript are preserved.", recoveryAction: .retry, retryable: true)
        case .processingFailed:
            return Self(code: code, message: "On-device analysis stopped before minutes were finished. Your recording and completed transcript are preserved.", recoveryAction: .retry, retryable: true)
        case .leaseConflict:
            return Self(code: code, message: "This meeting is already being processed. Wait for it to finish or pause it before retrying.", recoveryAction: .processNow, retryable: true)
        case .schedulingFailed:
            return Self(code: code, message: "Background processing could not be scheduled. Open this meeting and tap Process Now.", recoveryAction: .processNow, retryable: true)
        }
    }
}

public struct AnalysisModelRequirement: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let revision: String
    public let bytes: Int64

    public init(profile: ModelProfile) {
        id = profile.id
        name = profile.name
        revision = profile.revision
        bytes = profile.downloadBytes
    }
}

public struct AnalysisJobRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { meetingID }
    public let meetingID: UUID
    public var sourceFingerprint: String
    public var checkpointVersion: String
    public var state: AnalysisJobState
    public var currentStage: AnalysisStage?
    public var requiredModels: [AnalysisModelRequirement]
    public var attemptCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var owner: AnalysisExecutionOwner?
    public var lastOwner: AnalysisExecutionOwner?
    public var leaseID: UUID?
    public var leaseUpdatedAt: Date?
    public var warning: String?
    public var failure: AnalysisFailure?

    public init(meetingID: UUID, sourceFingerprint: String, checkpointVersion: String,
                state: AnalysisJobState = .queued, currentStage: AnalysisStage? = .preparing,
                requiredModels: [AnalysisModelRequirement], now: Date = Date()) {
        self.meetingID = meetingID
        self.sourceFingerprint = sourceFingerprint
        self.checkpointVersion = checkpointVersion
        self.state = state
        self.currentStage = currentStage
        self.requiredModels = requiredModels
        self.attemptCount = 0
        self.createdAt = now
        self.updatedAt = now
    }
}

public struct AnalysisJobLease: Codable, Sendable, Equatable {
    public let meetingID: UUID
    public let id: UUID
    public let owner: AnalysisExecutionOwner
}

public enum AnalysisJobStoreError: LocalizedError, Equatable {
    case corrupt
    case leaseConflict
    case leaseLost
    case missingJob

    public var errorDescription: String? {
        switch self {
        case .corrupt: return AnalysisFailure.stable(.jobStoreCorrupt).message
        case .leaseConflict: return AnalysisFailure.stable(.leaseConflict).message
        case .leaseLost: return "The analysis execution lease expired. The saved job can be retried."
        case .missingJob: return "The saved analysis job could not be found."
        }
    }
}

/// Versioned sidecar storage for analysis orchestration. The whole envelope is
/// replaced atomically, protected until first unlock, and excluded from backup.
public actor AnalysisJobStore {
    private struct Envelope: Codable {
        let version: Int
        var jobs: [UUID: AnalysisJobRecord]
    }

    public static let shared = AnalysisJobStore()
    public let fileURL: URL
    private let now: @Sendable () -> Date

    public init(fileURL: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support.appendingPathComponent("OfflineIntelligence/AnalysisJobs/jobs-v1.json")
        }
        self.now = now
    }

    public func all() throws -> [AnalysisJobRecord] {
        Array(try load().jobs.values).sorted { $0.createdAt < $1.createdAt }
    }

    public func get(_ meetingID: UUID) throws -> AnalysisJobRecord? {
        try load().jobs[meetingID]
    }

    @discardableResult
    public func upsert(_ record: AnalysisJobRecord) throws -> AnalysisJobRecord {
        var envelope = try load()
        let timestamp = now()
        if let current = envelope.jobs[record.meetingID], current.leaseID != nil,
           current.leaseID != record.leaseID, let leasedAt = current.leaseUpdatedAt,
           timestamp.timeIntervalSince(leasedAt) < 15 * 60 {
            throw AnalysisJobStoreError.leaseConflict
        }
        var value = record
        value.updatedAt = timestamp
        envelope.jobs[value.meetingID] = value
        try save(envelope)
        return value
    }

    @discardableResult
    public func enqueue(_ record: AnalysisJobRecord) throws -> AnalysisJobRecord {
        var envelope = try load()
        let timestamp = now()
        if let current = envelope.jobs[record.meetingID], current.leaseID != nil,
           let leasedAt = current.leaseUpdatedAt,
           timestamp.timeIntervalSince(leasedAt) < 15 * 60 {
            throw AnalysisJobStoreError.leaseConflict
        }
        var value = record
        value.state = .queued
        value.failure = nil
        value.owner = nil
        value.leaseID = nil
        value.leaseUpdatedAt = nil
        value.updatedAt = timestamp
        envelope.jobs[value.meetingID] = value
        try save(envelope)
        return value
    }

    public func claim(_ meetingID: UUID, owner: AnalysisExecutionOwner,
                      staleAfter: TimeInterval = 15 * 60) throws -> AnalysisJobLease {
        var envelope = try load()
        guard var record = envelope.jobs[meetingID] else { throw AnalysisJobStoreError.missingJob }
        let timestamp = now()
        if record.leaseID != nil, let leasedAt = record.leaseUpdatedAt,
           timestamp.timeIntervalSince(leasedAt) < staleAfter {
            throw AnalysisJobStoreError.leaseConflict
        }
        let lease = AnalysisJobLease(meetingID: meetingID, id: UUID(), owner: owner)
        record.owner = owner
        record.lastOwner = owner
        record.leaseID = lease.id
        record.leaseUpdatedAt = timestamp
        record.startedAt = record.startedAt ?? timestamp
        record.updatedAt = timestamp
        record.attemptCount += 1
        record.state = .running
        record.failure = nil
        envelope.jobs[meetingID] = record
        try save(envelope)
        return lease
    }

    public func transition(_ lease: AnalysisJobLease, state: AnalysisJobState,
                           stage: AnalysisStage?, warning: String? = nil) throws {
        try mutateLease(lease) { record, timestamp in
            record.state = state
            record.currentStage = stage
            record.warning = warning ?? record.warning
            record.leaseUpdatedAt = timestamp
        }
    }

    public func setState(_ meetingID: UUID, state: AnalysisJobState,
                         stage: AnalysisStage?, failure: AnalysisFailure? = nil) throws {
        var envelope = try load()
        guard var record = envelope.jobs[meetingID] else { throw AnalysisJobStoreError.missingJob }
        if record.leaseID != nil, let leasedAt = record.leaseUpdatedAt,
           now().timeIntervalSince(leasedAt) < 15 * 60 {
            throw AnalysisJobStoreError.leaseConflict
        }
        record.state = state
        record.currentStage = stage
        record.failure = failure
        record.updatedAt = now()
        envelope.jobs[meetingID] = record
        try save(envelope)
    }

    public func release(_ lease: AnalysisJobLease) throws {
        try mutateLease(lease) { record, _ in
            record.owner = nil
            record.leaseID = nil
            record.leaseUpdatedAt = nil
        }
    }

    public func complete(_ lease: AnalysisJobLease, warning: String? = nil) throws {
        try mutateLease(lease) { record, timestamp in
            record.state = .completed
            record.currentStage = .completed
            record.completedAt = timestamp
            record.warning = warning ?? record.warning
            record.failure = nil
            record.owner = nil
            record.leaseID = nil
            record.leaseUpdatedAt = nil
        }
    }

    public func fail(_ lease: AnalysisJobLease, failure: AnalysisFailure) throws {
        try mutateLease(lease) { record, _ in
            record.state = .failed
            record.failure = failure
            record.owner = nil
            record.leaseID = nil
            record.leaseUpdatedAt = nil
        }
    }

    public func pause(_ lease: AnalysisJobLease) throws {
        try mutateLease(lease) { record, _ in
            record.state = .paused
            record.owner = nil
            record.leaseID = nil
            record.leaseUpdatedAt = nil
        }
    }

    public func remove(_ meetingID: UUID) throws {
        var envelope = try load()
        envelope.jobs.removeValue(forKey: meetingID)
        try save(envelope)
    }

    private func mutateLease(_ lease: AnalysisJobLease,
                             _ mutation: (inout AnalysisJobRecord, Date) -> Void) throws {
        var envelope = try load()
        guard var record = envelope.jobs[lease.meetingID] else { throw AnalysisJobStoreError.missingJob }
        guard record.leaseID == lease.id, record.owner == lease.owner else { throw AnalysisJobStoreError.leaseLost }
        let timestamp = now()
        mutation(&record, timestamp)
        record.updatedAt = timestamp
        envelope.jobs[lease.meetingID] = record
        try save(envelope)
    }

    private func load() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Envelope(version: 1, jobs: [:]) }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.version == 1 else { throw AnalysisJobStoreError.corrupt }
            return envelope
        } catch let error as AnalysisJobStoreError {
            throw error
        } catch {
            throw AnalysisJobStoreError.corrupt
        }
    }

    private func save(_ envelope: Envelope) throws {
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoderCompatible = try encoder.encode(envelope)
        // Decode with the matching strategy before replacing durable state.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(Envelope.self, from: decoderCompatible)
        try decoderCompatible.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var persistedFile = fileURL
        try persistedFile.setResourceValues(values)
    }
}
