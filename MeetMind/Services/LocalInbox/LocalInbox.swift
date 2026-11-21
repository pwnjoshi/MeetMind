import Foundation

/// Kind of local app event shown in the notifications inbox.
public enum LocalInboxKind: String, Sendable, Equatable {
    case minutesReady
    case processingFailed
    case taskDue
    case taskOverdue
    case taskCompleted

    public var title: String {
        switch self {
        case .minutesReady: return "Minutes Ready"
        case .processingFailed: return "Processing Needs Attention"
        case .taskDue: return "Task Due Soon"
        case .taskOverdue: return "Task Overdue"
        case .taskCompleted: return "Task Completed"
        }
    }

    public var systemImage: String {
        switch self {
        case .minutesReady: return "doc.text"
        case .processingFailed: return "exclamationmark.triangle"
        case .taskDue: return "clock"
        case .taskOverdue: return "exclamationmark.circle"
        case .taskCompleted: return "checkmark.circle"
        }
    }
}

/// One derived inbox entry. Entries are computed from saved data, never invented.
public struct LocalInboxItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: LocalInboxKind
    public let meetingID: UUID
    public let detail: String
    public let date: Date

    public init(id: String, kind: LocalInboxKind, meetingID: UUID, detail: String, date: Date) {
        self.id = id
        self.kind = kind
        self.meetingID = meetingID
        self.detail = detail
        self.date = date
    }
}

/// Value snapshot of a meeting used for inbox derivation.
public struct LocalInboxMeetingInput: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let date: Date
    public let analysisState: String?
    public let hasMinutes: Bool

    public init(id: UUID, title: String, date: Date, analysisState: String?, hasMinutes: Bool) {
        self.id = id
        self.title = title
        self.date = date
        self.analysisState = analysisState
        self.hasMinutes = hasMinutes
    }
}

/// Value snapshot of an action item used for inbox derivation.
public struct LocalInboxTaskInput: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let meetingID: UUID?
    public let meetingTitle: String?
    public let dueDate: Date?
    public let isCompleted: Bool
    public let completedAt: Date?

    public init(id: UUID, title: String, meetingID: UUID?, meetingTitle: String?,
                dueDate: Date?, isCompleted: Bool, completedAt: Date?) {
        self.id = id
        self.title = title
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}

/// Deterministic derivation of inbox items from saved meetings and tasks.
public enum LocalInboxBuilder {
    /// Open tasks due within this window (or already overdue) appear in the inbox.
    public static let dueSoonWindow: TimeInterval = 3 * 24 * 60 * 60
    /// Completed tasks stay in the inbox for this long.
    public static let completedWindow: TimeInterval = 7 * 24 * 60 * 60
    public static let maximumItems = 60

    public static func items(meetings: [LocalInboxMeetingInput],
                             tasks: [LocalInboxTaskInput],
                             now: Date) -> [LocalInboxItem] {
        var result: [LocalInboxItem] = []

        for meeting in meetings {
            if meeting.analysisState == "completed", meeting.hasMinutes {
                result.append(LocalInboxItem(
                    id: "minutes-\(meeting.id.uuidString)", kind: .minutesReady,
                    meetingID: meeting.id, detail: "\(meeting.title) · Ready to read", date: meeting.date))
            } else if meeting.analysisState == "failed" {
                result.append(LocalInboxItem(
                    id: "failed-\(meeting.id.uuidString)", kind: .processingFailed,
                    meetingID: meeting.id, detail: "\(meeting.title) · Open to retry", date: meeting.date))
            }
        }

        for task in tasks {
            guard let meetingID = task.meetingID else { continue }
            let source = task.meetingTitle.map { "\(task.title) · \($0)" } ?? task.title
            if task.isCompleted {
                if let completedAt = task.completedAt,
                   completedAt <= now, now.timeIntervalSince(completedAt) <= completedWindow {
                    result.append(LocalInboxItem(
                        id: "done-\(task.id.uuidString)", kind: .taskCompleted,
                        meetingID: meetingID, detail: source, date: completedAt))
                }
            } else if let due = task.dueDate {
                if due < now {
                    result.append(LocalInboxItem(
                        id: "overdue-\(task.id.uuidString)", kind: .taskOverdue,
                        meetingID: meetingID, detail: source, date: due))
                } else if due.timeIntervalSince(now) <= dueSoonWindow {
                    result.append(LocalInboxItem(
                        id: "due-\(task.id.uuidString)", kind: .taskDue,
                        meetingID: meetingID, detail: source, date: due))
                }
            }
        }

        let sorted = result.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id < $1.id
        }
        return Array(sorted.prefix(maximumItems))
    }
}

/// Stores which inbox entries the user has opened. Local UserDefaults only.
@MainActor
public final class LocalInboxReadStore {
    public static let defaultsKey = "Manent_LocalInbox_ReadIDs"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var readIDs: Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    public func isRead(_ id: String) -> Bool {
        readIDs.contains(id)
    }

    public func markRead(_ id: String) {
        var ids = readIDs
        ids.insert(id)
        defaults.set(Array(ids).sorted(), forKey: Self.defaultsKey)
    }

    public func markAllRead(_ items: [LocalInboxItem]) {
        var ids = readIDs
        for item in items { ids.insert(item.id) }
        defaults.set(Array(ids).sorted(), forKey: Self.defaultsKey)
    }

    public func unreadCount(in items: [LocalInboxItem]) -> Int {
        let ids = readIDs
        return items.filter { !ids.contains($0.id) }.count
    }

    public func reset() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    public func remove(meetingID: UUID, actionItemIDs: [UUID]) {
        let meetingSuffix = meetingID.uuidString
        let taskSuffixes = Set(actionItemIDs.map(\.uuidString))
        let remaining = readIDs.filter { id in
            if id.hasSuffix(meetingSuffix) { return false }
            return !taskSuffixes.contains(where: { id.hasSuffix($0) })
        }
        if remaining.isEmpty {
            reset()
        } else {
            defaults.set(Array(remaining).sorted(), forKey: Self.defaultsKey)
        }
    }
}
