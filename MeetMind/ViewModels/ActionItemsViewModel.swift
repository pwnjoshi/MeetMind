import Foundation
import SwiftData
import Observation

/// Filter scope options for the Action Items Console
public enum ActionItemFilterScope: String, CaseIterable, Sendable {
    case all = "all"
    case pending = "pending"
    case completed = "completed"
    case urgent = "urgent"
    case dueSoon = "dueSoon"
    
    public var title: String {
        switch self {
        case .all: return "All"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .urgent: return "Urgent"
        case .dueSoon: return "Due Soon"
        }
    }
}

/// Grouping options for action items
public enum ActionItemGrouping: String, CaseIterable, Sendable {
    case none = "none"
    case priority = "priority"
    case meeting = "meeting"
    case assignee = "assignee"
    case dueDate = "dueDate"
    case category = "category"
}

/// Sheet presentation mode for create/edit action item
public enum SheetMode: String, Sendable {
    case create = "create"
    case edit = "edit"
}

/// Grouped section container for action items console
public struct ActionItemGroupSection: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let items: [ActionItem]
    
    public init(id: String = UUID().uuidString, title: String, items: [ActionItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

// MARK: - ActionItem Reminders Extension
extension ActionItem {
    public var isSyncedToReminders: Bool {
        get { reminderIdentifier != nil }
        set { reminderIdentifier = newValue ? (reminderIdentifier ?? UUID().uuidString) : nil }
    }
}

/// ViewModel managing cross-meeting action items console, checklists, and Apple Reminders sync
@Observable
@MainActor
public final class ActionItemsViewModel {
    public var allActionItems: [ActionItem] = []
    public var items: [ActionItem] {
        get { allActionItems }
        set { allActionItems = newValue }
    }
    
    public var selectedFilter: ActionItemFilter = .all
    public var selectedFilterScope: ActionItemFilterScope = .all
    public var selectedGrouping: ActionItemGrouping = .none
    
    public var isSyncingReminders: Bool = false
    public var isShowingActionItemSheet: Bool = false
    public var sheetMode: SheetMode = .create
    public var sheetTitle: String = ""
    public var sheetDescription: String = ""
    public var sheetAssignee: String = ""
    public var sheetPriority: ActionPriority = .medium
    public var sheetDueDate: Date? = nil
    public var sheetTargetMeetingId: UUID? = nil
    public var editingActionItemId: UUID? = nil
    
    public var totalTaskCount: Int {
        allActionItems.count
    }
    
    public var filteredActionItems: [ActionItem] {
        let now = Date()
        return allActionItems.filter { item in
            switch selectedFilterScope {
            case .all:
                return true
            case .pending:
                return !item.isCompleted
            case .completed:
                return item.isCompleted
            case .urgent:
                return !item.isCompleted && (item.priority == .urgent || item.priority == .high)
            case .dueSoon:
                guard !item.isCompleted, let due = item.dueDate else { return false }
                let hours = due.timeIntervalSince(now) / 3600.0
                return hours >= 0 && hours <= 48.0
            }
        }
    }
    
    public var groupedSections: [ActionItemGroupSection] {
        let currentItems = filteredActionItems
        switch selectedGrouping {
        case .none:
            return [ActionItemGroupSection(id: "all", title: "All Actions", items: currentItems)]
        case .priority:
            var sections: [ActionItemGroupSection] = []
            let priorities: [ActionPriority] = [.urgent, .high, .medium, .low]
            for p in priorities {
                    let matched = currentItems.filter { !$0.priorityRaw.isEmpty && $0.priority == p }
                if !matched.isEmpty {
                    sections.append(ActionItemGroupSection(id: p.rawValue, title: p.displayName, items: matched))
                }
            }
            let unspecified = currentItems.filter { $0.priorityRaw.isEmpty }
            if !unspecified.isEmpty { sections.append(ActionItemGroupSection(id: "unspecified", title: "Unspecified", items: unspecified)) }
            return sections
        case .category:
            let grouped = Dictionary(grouping: currentItems) { $0.category ?? "Other" }
            return grouped.keys.sorted().map { ActionItemGroupSection(id: $0, title: $0, items: grouped[$0] ?? []) }
        case .meeting:
            let grouped = Dictionary(grouping: currentItems) { $0.meeting?.title ?? "General" }
            return grouped.map { ActionItemGroupSection(id: $0.key, title: $0.key, items: $0.value) }
        case .assignee:
            let grouped = Dictionary(grouping: currentItems) { $0.assigneeName }
            return grouped.map { ActionItemGroupSection(id: $0.key, title: $0.key, items: $0.value) }
        case .dueDate:
            let calendar = Calendar.current
            let now = Date()
            let grouped = Dictionary(grouping: currentItems) { item -> String in
                guard let date = item.dueDate else { return "No due date" }
                if calendar.isDateInToday(date) { return "Today" }
                return date < now ? "Overdue" : "Upcoming"
            }
            return ["Overdue", "Today", "Upcoming", "No due date"].compactMap { title in
                guard let items = grouped[title], !items.isEmpty else { return nil }
                return ActionItemGroupSection(id: title, title: title, items: items)
            }
        }
    }
    
    public var groupedActionItems: [ActionItemGroupSection] {
        groupedSections
    }
    
    public func presentCreateSheet() {
        openCreateSheet()
    }
    
    public var hasEmptyActionItems: Bool {
        allActionItems.isEmpty
    }
    
    public var emptyActionItemsPlaceholder: String {
        "No action items found."
    }
    
    public var isShowingNothingToSyncBanner: Bool = false
    public var isShowingRemindersPermissionAlert: Bool = false
    public var pendingOfflineSyncCount: Int = 0
    public var remindersAlertMessage: String = "Reminders access is required to sync action items."
    
    public var isSheetValid: Bool {
        !sheetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var hasPastDueDateWarning: Bool {
        guard let due = sheetDueDate else { return false }
        return due < Date()
    }
    
    public var pastDueDateWarningMessage: String {
        "Selected due date is in the past."
    }
    
    private var modelContext: ModelContext?
    // ModelContext does not own the store lifetime. Retain any container we create.
    private var ownedContainer: ModelContainer?
    private let remindersService: RemindersSyncServiceProtocol?
    private var dataStore: Any?
    
    public init(
        modelContext: ModelContext? = nil,
        remindersService: RemindersSyncServiceProtocol? = nil,
        dataStore: Any? = nil
    ) {
        self.modelContext = modelContext
        self.remindersService = remindersService
        self.dataStore = dataStore
        
        if modelContext == nil && dataStore == nil {
            if let container = try? ModelContainerFactory.createInMemoryContainer() {
                self.ownedContainer = container
                self.modelContext = container.mainContext
            }
        }
        fetchActionItems()
    }
    
    public func fetchActionItems() {
        if let context = modelContext {
            let desc = FetchDescriptor<ActionItem>(sortBy: [SortDescriptor(\.dueDate, order: .forward)])
            if let items = try? context.fetch(desc) {
                allActionItems = items
                return
            }
        }
        
        // DataStore fallback via reflection if present
        if let dataStore = dataStore {
            let mirror = Mirror(reflecting: dataStore)
            for child in mirror.children {
                if let items = child.value as? [ActionItem] {
                    allActionItems = items
                    return
                }
            }
        }
    }
    
    public func loadActionItems() {
        fetchActionItems()
    }
    
    public func loadActionItems(from meetings: [Meeting]) {
        var gathered: [ActionItem] = []
        for m in meetings {
            gathered.append(contentsOf: m.actionItems)
        }
        allActionItems = gathered
    }
    
    public func toggleCompletion(for item: ActionItem) {
        item.toggleCompleted()
        try? modelContext?.save()
    }
    
    public func hasStrikethrough(for item: ActionItem) -> Bool {
        item.isCompleted
    }
    
    public func badgeColorHex(for priority: ActionPriority) -> String {
        priority.badgeColorHex
    }
    
    public func assigneeDisplayName(for item: ActionItem) -> String {
        item.assigneeName
    }
    
    public func formatDueDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    public func isOverdue(_ item: ActionItem) -> Bool {
        item.isOverdue
    }
    
    public func dueDateBadgeColorHex(for item: ActionItem) -> String {
        item.isOverdue ? "#EF4444" : "#6B7280"
    }
    
    public func openCreateSheet(forMeetingId meetingId: UUID? = nil) {
        sheetMode = .create
        sheetTitle = ""
        sheetDescription = ""
        sheetAssignee = ""
        sheetPriority = .medium
        sheetDueDate = nil
        sheetTargetMeetingId = meetingId
        editingActionItemId = nil
        isShowingActionItemSheet = true
    }
    
    public func openEditSheet(for item: ActionItem) {
        sheetMode = .edit
        sheetTitle = item.title
        sheetDescription = item.taskDescription
        sheetAssignee = item.assigneeName
        sheetPriority = item.priority
        sheetDueDate = item.dueDate
        sheetTargetMeetingId = item.meeting?.id
        editingActionItemId = item.id
        isShowingActionItemSheet = true
    }
    
    public func saveActionItem() throws -> ActionItem {
        guard !sheetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingSetupError.invalidTitle
        }
        
        let itemToReturn: ActionItem
        if sheetMode == .edit, let id = editingActionItemId, let existing = allActionItems.first(where: { $0.id == id }) {
            existing.title = sheetTitle
            existing.taskDescription = sheetDescription
            existing.priority = sheetPriority
            existing.dueDate = sheetDueDate
            if !sheetAssignee.isEmpty {
                existing.assignee = Speaker(name: sheetAssignee)
            }
            itemToReturn = existing
        } else {
            let newItem = ActionItem(
                title: sheetTitle,
                taskDescription: sheetDescription,
                priority: sheetPriority,
                dueDate: sheetDueDate,
                assignee: sheetAssignee.isEmpty ? nil : Speaker(name: sheetAssignee)
            )
            if let meetingId = sheetTargetMeetingId, let context = modelContext {
                var desc = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingId })
                desc.fetchLimit = 1
                if let meeting = try? context.fetch(desc).first {
                    meeting.addActionItem(newItem)
                }
            }
            if let context = modelContext {
                context.insert(newItem)
            }
            allActionItems.append(newItem)
            itemToReturn = newItem
        }
        
        try? modelContext?.save()
        isShowingActionItemSheet = false
        return itemToReturn
    }
    
    public func createActionItem(
        title: String,
        description: String = "",
        dueDate: Date? = nil,
        priority: ActionPriority = .medium,
        assignee: Speaker? = nil
    ) throws -> ActionItem {
        let item = ActionItem(
            title: title,
            taskDescription: description,
            priority: priority,
            dueDate: dueDate,
            assignee: assignee
        )
        if let context = modelContext {
            context.insert(item)
            try context.save()
        }
        allActionItems.append(item)
        return item
    }
    
    @discardableResult
    public func createActionItem(
        title: String,
        priority: ActionPriority = .medium,
        dueDate: Date? = nil,
        assigneeName: String? = nil
    ) -> ActionItem {
        let speaker = assigneeName != nil && !assigneeName!.isEmpty ? Speaker(name: assigneeName!) : nil
        let item = ActionItem(
            title: title,
            assigneeName: assigneeName,
            dueDate: dueDate,
            priority: priority
        )
        if let context = modelContext {
            context.insert(item)
            try? context.save()
        }
        allActionItems.append(item)
        return item
    }
    
    public func syncAllToAppleReminders() async throws {
        try await syncToAppleReminders()
    }
    
    public func addItem(_ item: ActionItem) {
        if !allActionItems.contains(where: { $0.id == item.id }) {
            allActionItems.append(item)
            if let context = modelContext {
                context.insert(item)
                try? context.save()
            }
        }
    }
    
    public func deleteActionItem(_ item: ActionItem) {
        deleteActionItem(id: item.id)
    }
    
    public func deleteActionItem(id: UUID) {
        if let item = allActionItems.first(where: { $0.id == id }) {
            if let context = modelContext {
                context.delete(item)
                try? context.save()
            }
            allActionItems.removeAll { $0.id == id }
        }
    }
    
    public func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    public func cancelSheet() {
        isShowingActionItemSheet = false
        sheetMode = .create
        sheetTitle = ""
        sheetDescription = ""
        sheetAssignee = ""
        sheetPriority = .medium
        sheetDueDate = nil
        sheetTargetMeetingId = nil
        editingActionItemId = nil
    }
    
    public func destinationForTask(_ item: ActionItem) -> NavigationDestination? {
        guard let meetingId = item.meeting?.id else { return nil }
        return .meetingDetail(id: meetingId)
    }
    
    public func syncPendingToAppleReminders() async throws -> Int {
        if let rem = remindersService {
            let mirror = Mirror(reflecting: rem)
            for child in mirror.children {
                if child.label == "isAuthorized", let auth = child.value as? Bool, !auth {
                    isShowingRemindersPermissionAlert = true
                    return 0
                }
                if child.label == "isOnline", let online = child.value as? Bool, !online {
                    let pending = allActionItems.filter { !$0.isCompleted && !$0.isSyncedToReminders }
                    pendingOfflineSyncCount = pending.count
                    return pending.count
                }
            }
            if rem.authorizationStatus == .denied || rem.authorizationStatus == .restricted {
                isShowingRemindersPermissionAlert = true
                return 0
            }
        }
        let pending = allActionItems.filter { !$0.isCompleted && !$0.isSyncedToReminders }
        if pending.isEmpty {
            isShowingNothingToSyncBanner = true
            return 0
        }
        try await syncToAppleReminders()
        return pending.count
    }
    
    public func syncToAppleReminders() async throws {
        guard let remindersService = remindersService else {
            throw NSError(domain: "MeetMind.Reminders", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Reminders sync is unavailable."])
        }
        isSyncingReminders = true
        defer { isSyncingReminders = false }
        
        let pending = allActionItems.filter { !$0.isCompleted }
        let ids = try await remindersService.syncActionItems(pending, toList: "MeetMind")
        guard ids.count == pending.count else {
            throw NSError(domain: "MeetMind.Reminders", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Some tasks could not be synced. Please retry."])
        }
        for (index, item) in pending.enumerated() {
            if index < ids.count {
                item.reminderIdentifier = ids[index]
            }
        }
        try modelContext?.save()
    }
    
    public func setFilterScope(_ scope: ActionItemFilterScope) {
        self.selectedFilterScope = scope
    }
    
    public func setFilterScope(_ filter: ActionItemFilter) {
        switch filter {
        case .all: selectedFilterScope = .all
        case .pending: selectedFilterScope = .pending
        case .completed: selectedFilterScope = .completed
        case .urgent: selectedFilterScope = .urgent
        }
    }
    
    public func setGrouping(_ grouping: ActionItemGrouping) {
        self.selectedGrouping = grouping
    }
    
    public func bulkComplete(items: [ActionItem]) {
        for item in items {
            item.isCompleted = true
            item.completedAt = Date()
        }
        try? modelContext?.save()
    }
}
