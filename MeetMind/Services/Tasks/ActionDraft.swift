import Foundation
import SwiftData

/// Editable values behind the New Action sheet and the task detail form.
public struct ActionDraft: Equatable, Sendable {
    public var title: String
    public var note: String
    public var dueDate: Date?
    /// Nil means unassigned.
    public var ownerName: String?
    public var meetingID: UUID?
    /// People typed in through "New Person" that are not meeting participants.
    public var extraOwners: [String]

    public init(
        title: String = "",
        note: String = "",
        dueDate: Date? = nil,
        ownerName: String? = nil,
        meetingID: UUID? = nil,
        extraOwners: [String] = []
    ) {
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.ownerName = ownerName
        self.meetingID = meetingID
        self.extraOwners = extraOwners
    }

    public init(item: ActionItem) {
        self.init(
            title: item.title,
            note: item.taskDescription,
            dueDate: item.dueDate,
            ownerName: item.assignee?.name,
            meetingID: item.meeting?.id
        )
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool { !trimmedTitle.isEmpty }
}

public enum ActionDraftError: LocalizedError, Equatable {
    case emptyTitle
    case storeUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Enter a title for the action."
        case .storeUnavailable: return "Actions cannot be saved right now."
        }
    }
}

/// Saves drafts as `ActionItem` values linked to a meeting and a speaker.
@MainActor
public enum ActionItemWriter {
    /// Finds the meeting participant, or an existing speaker with that name, or makes a new speaker.
    public static func speaker(named rawName: String, in meeting: Meeting?, context: ModelContext) -> Speaker? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let participant = meeting?.participants.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return participant
        }
        let descriptor = FetchDescriptor<Speaker>(predicate: #Predicate<Speaker> { $0.name == name })
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = Speaker(name: name)
        context.insert(created)
        return created
    }

    @discardableResult
    public static func create(from draft: ActionDraft, meetings: [Meeting], context: ModelContext) throws -> ActionItem {
        guard draft.isValid else { throw ActionDraftError.emptyTitle }
        let meeting = meetings.first { $0.id == draft.meetingID }
        let owner = draft.ownerName.flatMap { speaker(named: $0, in: meeting, context: context) }
        let item = ActionItem(
            title: draft.trimmedTitle,
            taskDescription: draft.note,
            priority: .medium,
            dueDate: draft.dueDate,
            assignee: owner
        )
        item.assignedByLocalUser = true
        context.insert(item)
        meeting?.addActionItem(item)
        do {
            try context.save()
        } catch {
            if let meeting {
                meeting.actionItems.removeAll { $0.id == item.id }
            }
            context.delete(item)
            throw error
        }
        return item
    }

    public static func apply(_ draft: ActionDraft, to item: ActionItem, meetings: [Meeting], context: ModelContext) throws {
        guard draft.isValid else { throw ActionDraftError.emptyTitle }
        let previousTitle = item.title
        let previousNote = item.taskDescription
        let previousDue = item.dueDate
        let previousAssignee = item.assignee
        let previousAssignedBy = item.assignedByLocalUser
        let previousMeeting = item.meeting

        let meeting = meetings.first { $0.id == draft.meetingID }
        item.title = draft.trimmedTitle
        item.taskDescription = draft.note
        item.dueDate = draft.dueDate

        let currentName = item.assignee?.name
        if (draft.ownerName ?? "") != (currentName ?? "") {
            if let name = draft.ownerName {
                item.assignee = speaker(named: name, in: meeting ?? item.meeting, context: context)
                item.assignedByLocalUser = true
            } else {
                item.assignee = nil
                item.assignedByLocalUser = nil
            }
        }
        if item.meeting?.id != meeting?.id {
            item.meeting = meeting
        }
        do {
            try context.save()
        } catch {
            item.title = previousTitle
            item.taskDescription = previousNote
            item.dueDate = previousDue
            item.assignee = previousAssignee
            item.assignedByLocalUser = previousAssignedBy
            item.meeting = previousMeeting
            throw error
        }
    }
}
