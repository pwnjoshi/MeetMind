import Foundation
import OfflineEngineKit
import SwiftData

public enum MeetingRecordEditError: LocalizedError, Equatable {
    case emptyText
    case duplicateDecision
    case missingMinutes
    case missingDecision
    case emptyTitle

    public var errorDescription: String? {
        switch self {
        case .emptyText: return "Enter some text."
        case .duplicateDecision: return "That decision is already recorded."
        case .missingMinutes: return "Decisions can be added once the minutes are ready."
        case .missingDecision: return "That decision no longer exists."
        case .emptyTitle: return "Enter a title for the action."
        }
    }
}

/// One line the Edit Minutes sheet wants in the decision list.
/// `originalIndex` points at the decision it started as, so its decided-by person follows an edit of its text.
public struct DecisionEdit: Equatable, Sendable {
    public var originalIndex: Int?
    public var text: String

    public init(originalIndex: Int?, text: String) {
        self.originalIndex = originalIndex
        self.text = text
    }
}

/// Every edit of decisions, actions and suggested tasks goes through here, so the Summary, the ActionItems,
/// the decided-by sidecar and everything built from `MeetingMinutesContent` change together.
/// Each call saves the model context; on failure it rolls back, restores the sidecar and throws.
@MainActor
public enum MeetingRecordEditor {
    private static let validCategories = ["Follow-up", "Research", "Create/Update", "Review/Approve", "Coordination", "Other"]

    // MARK: - Decisions

    /// Adds a decision at the end of `Summary.keyDecisions` with an optional decided-by person.
    public static func addDecision(_ text: String, decidedBy: UUID?, meeting: Meeting,
                                   context: ModelContext, store: MeetingRecordStore) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingRecordEditError.emptyText }
        guard let summary = meeting.summary else { throw MeetingRecordEditError.missingMinutes }
        let existing = summary.keyDecisions
        guard !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw MeetingRecordEditError.duplicateDecision
        }
        let newIndex = existing.count
        try commitDecisions(existing + [trimmed], summary: summary, meeting: meeting, context: context, store: store) {
            $0.setDecider(decidedBy, at: newIndex)
        }
    }

    /// Rewrites one decision and its decided-by person.
    public static func updateDecision(at index: Int, text: String, decidedBy: UUID?, meeting: Meeting,
                                      context: ModelContext, store: MeetingRecordStore) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingRecordEditError.emptyText }
        guard let summary = meeting.summary, summary.keyDecisions.indices.contains(index) else {
            throw MeetingRecordEditError.missingDecision
        }
        var updated = summary.keyDecisions
        updated[index] = trimmed
        try commitDecisions(updated, summary: summary, meeting: meeting, context: context, store: store) {
            $0.setDecider(decidedBy, at: index)
        }
    }

    /// Sets only the decided-by person. Touches the sidecar, not the Summary.
    public static func setDecider(_ id: UUID?, at index: Int, meeting: Meeting, store: MeetingRecordStore) throws {
        guard let summary = meeting.summary, summary.keyDecisions.indices.contains(index) else {
            throw MeetingRecordEditError.missingDecision
        }
        try store.update(meeting.id) { $0.setDecider(id, at: index) }
    }

    /// Removes a decision and shifts the decided-by metadata of the decisions after it.
    public static func deleteDecision(at index: Int, meeting: Meeting,
                                      context: ModelContext, store: MeetingRecordStore) throws {
        guard let summary = meeting.summary, summary.keyDecisions.indices.contains(index) else {
            throw MeetingRecordEditError.missingDecision
        }
        var updated = summary.keyDecisions
        updated.remove(at: index)
        try commitDecisions(updated, summary: summary, meeting: meeting, context: context, store: store) {
            $0.removeDecision(at: index)
        }
    }

    /// Replaces the whole decision list (Edit Minutes). Blank lines are dropped.
    /// A line that started as decision N keeps decision N's decided-by person even when its text changed.
    public static func applyDecisionEdits(_ lines: [DecisionEdit], meeting: Meeting,
                                          context: ModelContext, store: MeetingRecordStore) throws {
        guard let summary = meeting.summary else {
            if lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw MeetingRecordEditError.missingMinutes
            }
            return
        }
        var kept: [DecisionEdit] = []
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { kept.append(DecisionEdit(originalIndex: line.originalIndex, text: text)) }
        }
        let newDecisions = kept.map(\.text)
        if newDecisions == summary.keyDecisions && !kept.contains(where: { $0.originalIndex == nil }) {
            let identity = kept.enumerated().allSatisfy { $0.element.originalIndex == $0.offset }
            if identity { return }
        }
        try commitDecisions(newDecisions, summary: summary, meeting: meeting, context: context, store: store) { record in
            let previous = record.deciderIDs
            var rebuilt: [String] = []
            for line in kept {
                if let original = line.originalIndex, previous.indices.contains(original) {
                    rebuilt.append(previous[original])
                } else {
                    rebuilt.append("")
                }
            }
            record.deciderIDs = rebuilt
        }
    }

    static func addTranscriptDecision(_ text: String, segmentIDs: [UUID], meeting: Meeting,
                                      context: ModelContext, store: MeetingRecordStore) throws {
        guard let summary = meeting.summary else { throw MeetingRecordEditError.missingMinutes }
        let decisions = summary.keyDecisions.contains(text) ? summary.keyDecisions : summary.keyDecisions + [text]
        try commitDecisions(decisions, summary: summary, meeting: meeting, context: context, store: store) {
            var sources = $0.manualDecisionSources ?? [:]
            sources[text] = segmentIDs
            $0.manualDecisionSources = sources
        }
    }

    private static func commitDecisions(_ newDecisions: [String], summary: Summary, meeting: Meeting,
                                        context: ModelContext, store: MeetingRecordStore,
                                        record change: (inout MeetingRecordData) -> Void) throws {
        let previousDecisions = summary.keyDecisions
        let before = store.record(for: meeting.id)
        try store.update(meeting.id) { record in
            change(&record)
            record.manualDecisionSources = record.manualDecisionSources?.filter { newDecisions.contains($0.key) }
        }
        summary.keyDecisions = newDecisions
        do {
            try context.save()
        } catch {
            context.rollback()
            summary.keyDecisions = previousDecisions
            try? store.update(meeting.id) { $0 = before }
            throw error
        }
    }

    // MARK: - Actions

    @discardableResult
    public static func addAction(title: String, owner: Speaker?, dueDate: Date?, priority: ActionPriority,
                                 meeting: Meeting, context: ModelContext) throws -> ActionItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingRecordEditError.emptyTitle }
        let item = ActionItem(id: UUID(), title: trimmed, taskDescription: "", isCompleted: false,
                              priority: priority, dueDate: dueDate, completedAt: nil, assignee: owner,
                              reminderIdentifier: nil, meeting: nil)
        if owner != nil { item.assignedByLocalUser = true }
        context.insert(item)
        meeting.addActionItem(item)
        do {
            try context.save()
        } catch {
            context.rollback()
            meeting.actionItems.removeAll { $0.id == item.id }
            throw error
        }
        return item
    }

    public static func updateAction(_ item: ActionItem, title: String, owner: Speaker?, dueDate: Date?,
                                    priority: ActionPriority, context: ModelContext) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingRecordEditError.emptyTitle }
        let previousTitle = item.title
        let previousOwner = item.assignee
        let previousDue = item.dueDate
        let previousPriority = item.priorityRaw
        let previousAssignedByUser = item.assignedByLocalUser
        item.title = trimmed
        item.assignee = owner
        item.dueDate = dueDate
        item.priority = priority
        if owner != nil && previousOwner?.id != owner?.id { item.assignedByLocalUser = true }
        do {
            try context.save()
        } catch {
            context.rollback()
            item.title = previousTitle
            item.assignee = previousOwner
            item.dueDate = previousDue
            item.priorityRaw = previousPriority
            item.assignedByLocalUser = previousAssignedByUser
            throw error
        }
    }

    public static func setCompleted(_ item: ActionItem, _ completed: Bool, context: ModelContext) throws {
        guard item.isCompleted != completed else { return }
        let previousCompletedAt = item.completedAt
        item.isCompleted = completed
        item.completedAt = completed ? Date() : nil
        do {
            try context.save()
        } catch {
            context.rollback()
            item.isCompleted = !completed
            item.completedAt = previousCompletedAt
            throw error
        }
    }

    public static func deleteAction(_ item: ActionItem, from meeting: Meeting, context: ModelContext) throws {
        let previousOrder = meeting.actionItems
        meeting.actionItems.removeAll { $0.id == item.id }
        context.delete(item)
        do {
            try context.save()
        } catch {
            context.rollback()
            meeting.actionItems = previousOrder
            throw error
        }
    }

    // MARK: - Suggested tasks

    /// Accepts the suggestion as written: it becomes an action item and leaves the suggestion list.
    public static func acceptSuggestion(_ suggestion: MeetingTaskSuggestion, meeting: Meeting,
                                        context: ModelContext) throws {
        let category = validCategories.contains(suggestion.task.category) ? suggestion.task.category : "Other"
        let rawPriority = suggestion.task.priority ?? ""
        let priority = ActionPriority(rawValue: rawPriority) != nil ? rawPriority : ""
        try meeting.reviewTask(suggestion, title: suggestion.task.title, owner: suggestion.task.owner ?? "",
                               category: category, priority: priority, dueDate: nil, accept: true, context: context)
    }

    /// Discards the suggestion; it never becomes an action item.
    public static func discardSuggestion(_ suggestion: MeetingTaskSuggestion, meeting: Meeting,
                                         context: ModelContext) throws {
        try meeting.reviewTask(suggestion, title: suggestion.task.title, owner: "", category: "Other",
                               priority: "", dueDate: nil, accept: false, context: context)
    }
}
