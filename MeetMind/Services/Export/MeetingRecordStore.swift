import Foundation
import Observation

/// One person a copy of the minutes was addressed to. Only what the user chose is stored.
public struct SharedMinutesRecipient: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var email: String?
    public var colorHex: String

    public init(name: String, email: String?, colorHex: String) {
        self.name = name
        self.email = email
        self.colorHex = colorHex
    }
}

/// A local record that the user handed the minutes to Mail or the share sheet.
/// It never says whether anyone received or read the minutes. `bodyText` is the exact text that was handed over.
public struct SharedMinutesEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Channel: String, Codable, Sendable {
        case mail
        case shareSheet
    }

    public var id: UUID
    public var date: Date
    public var channel: Channel
    public var recipients: [SharedMinutesRecipient]
    public var subject: String
    public var bodyText: String

    public init(id: UUID = UUID(), date: Date = Date(), channel: Channel,
                recipients: [SharedMinutesRecipient], subject: String, bodyText: String) {
        self.id = id
        self.date = date
        self.channel = channel
        self.recipients = recipients
        self.subject = subject
        self.bodyText = bodyText
    }

    /// Short description of who the user addressed, for lists.
    public var recipientSummary: String {
        if recipients.isEmpty { return "Shared with the share sheet" }
        return MeetingRecordFormatting.joinedNames(recipients.map { MeetingRecordFormatting.firstName($0.name) })
    }
}

/// Remembers which person a voice label ("Speaker 1") was assigned to, so the People sheet can show and undo it.
public struct VoiceAssignment: Codable, Equatable, Sendable {
    public var label: String
    public var personID: UUID
    public var segmentIDs: [UUID]

    public init(label: String, personID: UUID, segmentIDs: [UUID]) {
        self.label = label
        self.personID = personID
        self.segmentIDs = segmentIDs
    }
}

/// Per-meeting record data that has no field on the SwiftData models.
public struct MeetingRecordData: Codable, Equatable, Sendable {
    /// Decided-by person ids, parallel to `Summary.keyDecisions`. An empty string means not set.
    public var deciderIDs: [String] = []
    public var keptPrivate: Bool = false
    public var keptPrivateAt: Date?
    public var shares: [SharedMinutesEntry] = []
    public var voiceAssignments: [VoiceAssignment] = []

    public init() {}

    public func decider(at index: Int) -> UUID? {
        guard deciderIDs.indices.contains(index) else { return nil }
        return UUID(uuidString: deciderIDs[index])
    }

    public mutating func setDecider(_ id: UUID?, at index: Int) {
        guard index >= 0 else { return }
        while deciderIDs.count <= index { deciderIDs.append("") }
        deciderIDs[index] = id?.uuidString ?? ""
    }

    public mutating func removeDecision(at index: Int) {
        guard deciderIDs.indices.contains(index) else { return }
        deciderIDs.remove(at: index)
    }

    /// Keeps each decision's decided-by person when the decision list is rewritten.
    /// A decision keeps its person only when its text is unchanged.
    public mutating func remapDeciders(oldDecisions: [String], newDecisions: [String]) {
        var pool: [(text: String, id: String)] = []
        for (offset, text) in oldDecisions.enumerated() {
            pool.append((text: text, id: deciderIDs.indices.contains(offset) ? deciderIDs[offset] : ""))
        }
        var result: [String] = []
        for text in newDecisions {
            if let match = pool.firstIndex(where: { $0.text == text }) {
                result.append(pool[match].id)
                pool.remove(at: match)
            } else {
                result.append("")
            }
        }
        deciderIDs = result
    }
}

public enum MeetingRecordFormatting {
    private static let honorifics: Set<String> = ["dr", "dr.", "mr", "mr.", "ms", "ms.", "mrs", "mrs.", "prof", "prof."]

    /// First given name, skipping titles such as "Dr.".
    public static func firstName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ").map(String.init)
        if let name = parts.first(where: { !honorifics.contains($0.lowercased()) }) { return name }
        return fullName
    }

    /// "A", "A and B", "A, B and C".
    public static func joinedNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

/// JSON file in Application Support holding `MeetingRecordData` keyed by meeting id.
@Observable
@MainActor
public final class MeetingRecordStore {
    public static let shared = MeetingRecordStore()

    @ObservationIgnored private let fileURL: URL?
    private var records: [String: MeetingRecordData] = [:]

    public nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MeetingRecords.json")
    }

    /// Pass `nil` for an in-memory store (used by tests).
    public init(fileURL: URL? = MeetingRecordStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: MeetingRecordData].self, from: data) {
            records = decoded
        }
    }

    public func record(for meetingID: UUID) -> MeetingRecordData {
        records[meetingID.uuidString] ?? MeetingRecordData()
    }

    /// Applies `change` and writes the file. When writing fails the in-memory record is restored and the error is thrown.
    public func update(_ meetingID: UUID, _ change: (inout MeetingRecordData) -> Void) throws {
        let key = meetingID.uuidString
        let previous = records[key]
        var updated = previous ?? MeetingRecordData()
        change(&updated)
        records[key] = updated
        do {
            try persist()
        } catch {
            records[key] = previous
            throw error
        }
    }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
