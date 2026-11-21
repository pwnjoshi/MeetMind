import Foundation
import Observation

public struct ReviewStateRecord: Codable, Sendable, Equatable {
    public var acknowledgements: Set<ReviewAcknowledgement>
    public var acknowledgementFingerprint: String?
    public var finalizationFingerprint: String?
    public var finalizedAt: Date?

    public init(acknowledgements: Set<ReviewAcknowledgement> = [], acknowledgementFingerprint: String? = nil,
                finalizationFingerprint: String? = nil, finalizedAt: Date? = nil) {
        self.acknowledgements = acknowledgements
        self.acknowledgementFingerprint = acknowledgementFingerprint
        self.finalizationFingerprint = finalizationFingerprint
        self.finalizedAt = finalizedAt
    }

    public func acknowledgements(validFor fingerprint: String) -> Set<ReviewAcknowledgement> {
        acknowledgementFingerprint == fingerprint ? acknowledgements : []
    }
}

public enum ReviewStateStoreError: LocalizedError, Equatable {
    case corrupt
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .corrupt:
            return "The saved minutes review state is unreadable. It was preserved instead of being overwritten."
        case .unsupportedVersion(let version):
            return "Minutes review state version \(version) is not supported by this version of Manent."
        }
    }
}

/// Versioned per-meeting review state. The complete envelope is validated and
/// atomically replaced under iOS file protection on every mutation.
@Observable
@MainActor
public final class ReviewStateStore: MeetingSidecarStore {
    private struct Envelope: Codable {
        let version: Int
        var records: [String: ReviewStateRecord]
    }

    public static let shared = ReviewStateStore()

    @ObservationIgnored public let fileURL: URL?
    @ObservationIgnored private var loadError: ReviewStateStoreError?
    private var records: [String: ReviewStateRecord] = [:]

    public nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Manent/Review/review-v1.json")
    }

    /// Pass nil for an in-memory store.
    public init(fileURL: URL? = ReviewStateStore.defaultFileURL()) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
            guard envelope.version == 1 else {
                loadError = .unsupportedVersion(envelope.version)
                return
            }
            records = envelope.records
        } catch {
            loadError = .corrupt
        }
    }

    public func record(for meetingID: UUID) throws -> ReviewStateRecord {
        if let loadError { throw loadError }
        return records[meetingID.uuidString] ?? ReviewStateRecord()
    }

    public func setAcknowledgement(_ acknowledgement: ReviewAcknowledgement, accepted: Bool,
                                   meetingID: UUID, contentFingerprint: String) throws {
        try update(meetingID) { record in
            if record.acknowledgementFingerprint != contentFingerprint {
                record.acknowledgements.removeAll()
                record.acknowledgementFingerprint = contentFingerprint
            }
            if accepted { record.acknowledgements.insert(acknowledgement) }
            else { record.acknowledgements.remove(acknowledgement) }
        }
    }

    public func finalize(meetingID: UUID, fingerprint: String, at date: Date = Date()) throws {
        try update(meetingID) {
            $0.finalizationFingerprint = fingerprint
            $0.finalizedAt = date
        }
    }

    /// Gives a pre-Stage-C finalized meeting its first fingerprint without
    /// changing any acknowledgement. Existing fingerprints are never replaced.
    public func bootstrapFinalization(meetingID: UUID, fingerprint: String, at date: Date = Date()) throws {
        let current = try record(for: meetingID)
        guard current.finalizationFingerprint == nil else { return }
        try update(meetingID) {
            $0.finalizationFingerprint = fingerprint
            $0.finalizedAt = date
        }
    }

    public func remove(meetingID: UUID) throws {
        if let loadError { throw loadError }
        let previous = records.removeValue(forKey: meetingID.uuidString)
        guard previous != nil else { return }
        do { try persist() }
        catch {
            records[meetingID.uuidString] = previous
            throw error
        }
    }

    public func eraseAll() throws {
        if let loadError { throw loadError }
        let previous = records
        records.removeAll()
        do {
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            records = previous
            throw error
        }
    }

    public var isEmpty: Bool { records.isEmpty }

    private func update(_ meetingID: UUID, change: (inout ReviewStateRecord) -> Void) throws {
        if let loadError { throw loadError }
        let key = meetingID.uuidString
        let previous = records[key]
        var next = previous ?? ReviewStateRecord()
        change(&next)
        records[key] = next
        do { try persist() }
        catch {
            records[key] = previous
            throw error
        }
    }

    private func persist() throws {
        guard let fileURL else { return }
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Envelope(version: 1, records: records))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(Envelope.self, from: data)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var persisted = fileURL
        try persisted.setResourceValues(values)
    }
}
