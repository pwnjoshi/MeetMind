import Foundation
import Observation
import CryptoKit

// MARK: - Review checklist

public struct ApprovalChecklistInput: Equatable, Sendable {
    public var minutesNeedFinalization: Bool
    public var participantCount: Int
    public var unnamedSpeakerCount: Int
    public var pendingTaskSuggestionCount: Int

    public init(minutesNeedFinalization: Bool, participantCount: Int, unnamedSpeakerCount: Int,
                pendingTaskSuggestionCount: Int) {
        self.minutesNeedFinalization = minutesNeedFinalization
        self.participantCount = participantCount
        self.unnamedSpeakerCount = unnamedSpeakerCount
        self.pendingTaskSuggestionCount = pendingTaskSuggestionCount
    }

    @MainActor
    public static func make(from meeting: Meeting) -> ApprovalChecklistInput {
        ApprovalChecklistInput(
            minutesNeedFinalization: meeting.minutesNeedFinalization == true,
            participantCount: meeting.participants.count,
            unnamedSpeakerCount: meeting.participants.count - meeting.namedAttendees.count,
            pendingTaskSuggestionCount: meeting.pendingTaskSuggestions.count)
    }
}

public struct ApprovalCheck: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case minutesFinalized, speakersNamed, tasksReviewed }
    public let kind: Kind
    public let title: String
    public let detail: String
    public let passed: Bool
    public var id: String { kind.rawValue }
}

public struct ApprovalChecklist: Equatable, Sendable {
    public let checks: [ApprovalCheck]

    public var failedChecks: [ApprovalCheck] { checks.filter { !$0.passed } }
    /// True when at least one check fails, which blocks submission.
    public var requiresReview: Bool { !failedChecks.isEmpty }

    public static func evaluate(_ input: ApprovalChecklistInput) -> ApprovalChecklist {
        let finalized = !input.minutesNeedFinalization
        let speakersNamed = input.participantCount > 0 && input.unnamedSpeakerCount == 0
        let tasksReviewed = input.pendingTaskSuggestionCount == 0

        let speakerDetail: String
        if input.participantCount == 0 {
            speakerDetail = "No speakers are saved for this meeting."
        } else if input.unnamedSpeakerCount > 0 {
            speakerDetail = input.unnamedSpeakerCount == 1
                ? "1 speaker still has a recording label."
                : "\(input.unnamedSpeakerCount) speakers still have recording labels."
        } else {
            speakerDetail = "Every speaker has a name."
        }

        let taskDetail: String
        if tasksReviewed {
            taskDetail = "No suggested tasks are waiting."
        } else {
            taskDetail = input.pendingTaskSuggestionCount == 1
                ? "1 suggested task is waiting for review."
                : "\(input.pendingTaskSuggestionCount) suggested tasks are waiting for review."
        }

        return ApprovalChecklist(checks: [
            ApprovalCheck(kind: .minutesFinalized, title: "Minutes finalized",
                          detail: finalized ? "These minutes are marked ready for review."
                                            : "Review and finalize the minutes first.",
                          passed: finalized),
            ApprovalCheck(kind: .speakersNamed, title: "All speakers named",
                          detail: speakerDetail, passed: speakersNamed),
            ApprovalCheck(kind: .tasksReviewed, title: "Suggested tasks reviewed",
                          detail: taskDetail, passed: tasksReviewed)
        ])
    }
}

// MARK: - Minutes text

public struct ApprovalMinutesInput: Equatable, Sendable {
    public var title: String
    public var date: Date
    public var attendees: [String]
    public var summary: String
    public var decisions: [String]
    public var actions: [SeriesActionSnapshot]

    public init(title: String, date: Date, attendees: [String], summary: String,
                decisions: [String], actions: [SeriesActionSnapshot]) {
        self.title = title
        self.date = date
        self.attendees = attendees
        self.summary = summary
        self.decisions = decisions
        self.actions = actions
    }

    @MainActor
    public static func make(from meeting: Meeting) -> ApprovalMinutesInput {
        ApprovalMinutesInput(
            title: meeting.title, date: meeting.createdAt,
            attendees: meeting.participants.map { $0.name },
            summary: meeting.summary?.executiveSummary ?? "",
            decisions: meeting.summary?.keyDecisions ?? [],
            actions: meeting.actionItems.map {
                SeriesActionSnapshot(title: $0.title, owner: $0.assignee?.name, isCompleted: $0.isCompleted)
            })
    }
}

public enum MinutesApprovalText {
    public static func build(_ input: ApprovalMinutesInput, dateFormatter: DateFormatter? = nil) -> String {
        let formatter: DateFormatter
        if let dateFormatter {
            formatter = dateFormatter
        } else {
            formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
        }
        var lines: [String] = ["Minutes: \(input.title)", formatter.string(from: input.date), ""]
        if !input.attendees.isEmpty {
            lines.append("Attendees: " + input.attendees.joined(separator: ", "))
            lines.append("")
        }
        let summary = input.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            lines.append("Summary")
            lines.append(summary)
            lines.append("")
        }
        if !input.decisions.isEmpty {
            lines.append("Decisions")
            lines.append(contentsOf: input.decisions.map { "- \($0)" })
            lines.append("")
        }
        if !input.actions.isEmpty {
            lines.append("Action items")
            lines.append(contentsOf: input.actions.map { action in
                let owner = action.owner.map { " (\($0))" } ?? ""
                return "- [\(action.isCompleted ? "x" : " ")] \(action.title)\(owner)"
            })
            lines.append("")
        }
        lines.append("Sent from Manent. These minutes are not approved until the reviewer replies.")
        return lines.joined(separator: "\n")
    }

    /// Short fingerprint of the exact text that was sent.
    public static func versionTag(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Local record

public struct MinutesApprovalRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Channel: String, Codable, Sendable { case mail, shareSheet }

    public var id: UUID
    public var meetingID: UUID
    public var reviewerName: String
    public var reviewerEmail: String?
    public var sentAt: Date
    public var channel: Channel
    public var versionTag: String

    public init(id: UUID = UUID(), meetingID: UUID, reviewerName: String, reviewerEmail: String?,
                sentAt: Date = Date(), channel: Channel, versionTag: String) {
        self.id = id
        self.meetingID = meetingID
        self.reviewerName = reviewerName
        self.reviewerEmail = reviewerEmail
        self.sentAt = sentAt
        self.channel = channel
        self.versionTag = versionTag
    }
}

/// Small JSON file in Application Support, keyed by meeting UUID. Stays on this iPhone.
@MainActor
@Observable
public final class MinutesApprovalStore {
    public static let shared = MinutesApprovalStore()

    private let fileURL: URL
    private var loadFailure: String?
    public private(set) var recordsByMeeting: [String: [MinutesApprovalRecord]]
    public private(set) var lastSaveError: String?

    public init(fileURL: URL? = nil) {
        let url = fileURL ?? MinutesApprovalStore.defaultURL()
        self.fileURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let data = try Data(contentsOf: url)
                self.recordsByMeeting = data.isEmpty ? [:] : try decoder.decode([String: [MinutesApprovalRecord]].self, from: data)
            } catch {
                self.recordsByMeeting = [:]
                self.loadFailure = error.localizedDescription
            }
        } else {
            self.recordsByMeeting = [:]
        }
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Manent", isDirectory: true)
            .appendingPathComponent("MinutesApprovals.json")
    }

    /// Newest first.
    public func records(for meetingID: UUID) -> [MinutesApprovalRecord] {
        (recordsByMeeting[meetingID.uuidString] ?? []).sorted { $0.sentAt > $1.sentAt }
    }

    public func add(_ record: MinutesApprovalRecord) {
        guard loadFailure == nil else {
            lastSaveError = SidecarStoreError.corrupt("Approval history").localizedDescription
            return
        }
        var list = recordsByMeeting[record.meetingID.uuidString] ?? []
        list.append(record)
        recordsByMeeting[record.meetingID.uuidString] = list
        do { try persist() }
        catch { lastSaveError = error.localizedDescription }
    }

    public func remove(meetingID: UUID) throws {
        if loadFailure != nil { throw SidecarStoreError.corrupt("Approval history") }
        let previous = recordsByMeeting.removeValue(forKey: meetingID.uuidString)
        guard previous != nil else { return }
        do { try persist() }
        catch {
            recordsByMeeting[meetingID.uuidString] = previous
            throw error
        }
    }

    public func eraseAll() throws {
        let previous = recordsByMeeting
        recordsByMeeting.removeAll()
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            loadFailure = nil
            lastSaveError = nil
        } catch {
            recordsByMeeting = previous
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    public var isEmpty: Bool { recordsByMeeting.isEmpty }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(recordsByMeeting).write(to: fileURL, options: .atomic)
        lastSaveError = nil
    }
}
