import Foundation
import SwiftData

// MARK: - Action Priority
public enum ActionPriority: String, Codable, CaseIterable, Comparable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"
    
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
    
    public var badgeColorHex: String {
        switch self {
        case .low: return "#6B7280"     // Slate Gray
        case .medium: return "#3B82F6"  // Live Blue
        case .high: return "#F59E0B"    // Warm Amber
        case .urgent: return "#EF4444"  // Coral Red
        }
    }
    
    public var iconName: String {
        switch self {
        case .low: return "arrow.down"
        case .medium: return "equal"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.3"
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }
    
    public static func < (lhs: ActionPriority, rhs: ActionPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

public typealias ActionItemPriority = ActionPriority

// MARK: - Action Item SwiftData Entity
@Model
public final class ActionItem: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var taskDescription: String
    public var isCompleted: Bool
    public var priorityRaw: String
    public var dueDate: Date?
    public var completedAt: Date?
    public var reminderIdentifier: String?
    public var category: String?
    public var sourceEvidence: String?
    public var sourceSuggestionID: String?
    
    // Relationships
    public var meeting: Meeting?
    
    @Relationship(deleteRule: .nullify, inverse: \Speaker.assignedActionItems)
    public var assignee: Speaker?
    
    public var priority: ActionPriority {
        get { ActionPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    public var priorityDisplayName: String { priorityRaw.isEmpty ? "Unspecified" : priority.displayName }
    
    public init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        isCompleted: Bool = false,
        priority: ActionPriority = .medium,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        assignee: Speaker? = nil,
        reminderIdentifier: String? = nil,
        meeting: Meeting? = nil
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.isCompleted = isCompleted
        self.priorityRaw = priority.rawValue
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.assignee = assignee
        self.reminderIdentifier = reminderIdentifier
        self.meeting = meeting
    }
    
    public convenience init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        isCompleted: Bool = false,
        priority: ActionPriority = .medium,
        dueDate: Date? = nil,
        completedAt: Date? = nil,
        assigneeName: String?,
        reminderIdentifier: String? = nil,
        meeting: Meeting? = nil
    ) {
        let speaker = assigneeName != nil && !assigneeName!.isEmpty ? Speaker(name: assigneeName!) : nil
        self.init(
            id: id,
            title: title,
            taskDescription: taskDescription,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            completedAt: completedAt,
            assignee: speaker,
            reminderIdentifier: reminderIdentifier,
            meeting: meeting
        )
    }
    
    public convenience init(
        title: String,
        assigneeName: String?,
        dueDate: Date? = nil,
        priority: ActionPriority = .medium,
        meeting: Meeting? = nil
    ) {
        let speaker = assigneeName != nil && !assigneeName!.isEmpty ? Speaker(name: assigneeName!) : nil
        self.init(
            id: UUID(),
            title: title,
            taskDescription: "",
            isCompleted: false,
            priority: priority,
            dueDate: dueDate,
            completedAt: nil,
            assignee: speaker,
            reminderIdentifier: nil,
            meeting: meeting
        )
    }
    
    public convenience init(
        title: String,
        assignee: Speaker?,
        dueDate: Date? = nil,
        priority: ActionPriority = .medium,
        meeting: Meeting? = nil
    ) {
        self.init(
            id: UUID(),
            title: title,
            taskDescription: "",
            isCompleted: false,
            priority: priority,
            dueDate: dueDate,
            completedAt: nil,
            assignee: assignee,
            reminderIdentifier: nil,
            meeting: meeting
        )
    }
    
    public var isOverdue: Bool {
        guard !isCompleted, let dueDate = dueDate else { return false }
        return dueDate < Date()
    }
    
    private static let cachedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    public var formattedDueDate: String? {
        guard let dueDate = dueDate else { return nil }
        return Self.cachedDateFormatter.string(from: dueDate)
    }
    
    public var assigneeName: String {
        assignee?.name ?? "Unassigned"
    }
    
    public func toggleCompleted() {
        isCompleted.toggle()
        completedAt = isCompleted ? Date() : nil
    }
}
