import Foundation

/// Which tasks the Actions list shows, by who owns or created them.
public enum ActionOwnerScope: String, CaseIterable, Sendable, Identifiable {
    case all
    case assignedToMe
    case assignedByMe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Actions"
        case .assignedToMe: return "Assigned to Me"
        case .assignedByMe: return "Assigned by Me"
        }
    }
}

/// Ordering inside each list section.
public enum ActionSortOrder: String, CaseIterable, Sendable, Identifiable {
    case dueDate
    case meeting

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dueDate: return "Due Date"
        case .meeting: return "Meeting"
        }
    }
}

/// Due-date text for a list row.
public struct ActionDueInfo: Equatable, Sendable {
    public let text: String
    public let isOverdue: Bool

    public init(text: String, isOverdue: Bool) {
        self.text = text
        self.isOverdue = isOverdue
    }
}

/// The two sections of the Actions list.
public struct ActionListSections {
    public let yours: [ActionItem]
    public let waitingOnOthers: [ActionItem]

    public var isEmpty: Bool { yours.isEmpty && waitingOnOthers.isEmpty }
}

/// Pure list rules for the Actions screen (scopes, sorting, sections, due text).
public enum ActionListLogic {
    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the task has an assignee whose name matches the local user.
    public static func isAssignedToLocalUser(_ item: ActionItem, localName: String) -> Bool {
        guard let name = item.assignee?.name else { return false }
        return normalized(name).caseInsensitiveCompare(normalized(localName)) == .orderedSame
    }

    /// True when someone other than the local user owns the task.
    /// Unassigned tasks belong to the local user.
    public static func isWaitingOnOthers(_ item: ActionItem, localName: String) -> Bool {
        guard item.assignee != nil else { return false }
        return !isAssignedToLocalUser(item, localName: localName)
    }

    public static func apply(scope: ActionOwnerScope, to items: [ActionItem], localName: String) -> [ActionItem] {
        switch scope {
        case .all:
            return items
        case .assignedToMe:
            return items.filter { isAssignedToLocalUser($0, localName: localName) }
        case .assignedByMe:
            return items.filter { $0.assignedByLocalUser == true }
        }
    }

    public static func sorted(_ items: [ActionItem], by order: ActionSortOrder) -> [ActionItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            switch order {
            case .dueDate:
                return dueOrder(lhs, rhs)
            case .meeting:
                let left = lhs.meeting?.title
                let right = rhs.meeting?.title
                if left != right {
                    guard let leftTitle = left else { return false }
                    guard let rightTitle = right else { return true }
                    return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
                }
                return dueOrder(lhs, rhs)
            }
        }
    }

    private static func dueOrder(_ lhs: ActionItem, _ rhs: ActionItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    public static func sections(_ items: [ActionItem], localName: String) -> ActionListSections {
        ActionListSections(
            yours: items.filter { !isWaitingOnOthers($0, localName: localName) },
            waitingOnOthers: items.filter { isWaitingOnOthers($0, localName: localName) }
        )
    }

    /// "Overdue", "Today", or a short date such as "Fri 27 Nov". Nil without a due date.
    public static func dueInfo(for item: ActionItem, now: Date = Date(), calendar: Calendar = .current) -> ActionDueInfo? {
        guard let due = item.dueDate else { return nil }
        if !item.isCompleted && calendar.startOfDay(for: due) < calendar.startOfDay(for: now) {
            return ActionDueInfo(text: "Overdue", isOverdue: true)
        }
        if calendar.isDate(due, inSameDayAs: now) {
            return ActionDueInfo(text: "Today", isOverdue: false)
        }
        return ActionDueInfo(text: shortDate(due), isOverdue: false)
    }

    public static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Owner choices for a task: the local user, the meeting's participants,
    /// people added in the form, and the current owner. Case-insensitive de-duplication.
    public static func ownerOptions(localName: String, meeting: Meeting?, extras: [String], current: String?) -> [String] {
        var result: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let name = normalized(raw)
            guard !name.isEmpty else { return }
            if !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                result.append(name)
            }
        }
        add(localName)
        for participant in meeting?.participants ?? [] { add(participant.name) }
        for extra in extras { add(extra) }
        add(current)
        return result
    }
}
