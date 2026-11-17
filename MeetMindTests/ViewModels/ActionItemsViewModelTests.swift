//
//  ActionItemsViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

public struct ActionItemValidationError: Error {}

public final class MockRemindersSyncService: RemindersSyncServiceProtocol, @unchecked Sendable {
    public var authorizationStatus: RemindersAuthorizationStatus { isAuthorized ? .authorized : .denied }
    public var isAuthorized: Bool = true
    public var isOnline: Bool = true
    public var dispatchedRemindersCount: Int = 0
    public var wasSyncDispatched: Bool = false
    public var targetReminderListName: String = "MeetMind"
    public var lastSyncedListTitle: String? = nil
    
    public init() {}
    
    public func requestAuthorization() async throws -> Bool {
        return isAuthorized
    }
    
    public func syncActionItems(_ items: [ActionItem], toList title: String) async throws -> [String] {
        guard isOnline else { throw NSError(domain: "Network", code: -1) }
        guard isAuthorized else { throw NSError(domain: "Auth", code: -1) }
        wasSyncDispatched = true
        lastSyncedListTitle = title
        targetReminderListName = title
        dispatchedRemindersCount += items.count
        return items.map { $0.id.uuidString }
    }
}

/// Comprehensive test suite covering Action Items Interactive Checklist,
/// Add / Edit Action Item Sheet, Sync to Apple Reminders (EventKit integration),
/// and Cross-Meeting Action Console aggregation, filtering, and grouping.
/// Corresponds to Features 48, 49, 50, and 54.
@MainActor
final class ActionItemsViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: ActionItemsViewModel!
    private var mockRemindersSyncService: MockRemindersSyncService!
    private var meeting1Id: UUID!
    private var meeting2Id: UUID!
    private var m1: Meeting!
    private var m2: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockRemindersSyncService = MockRemindersSyncService()
        
        meeting1Id = UUID()
        meeting2Id = UUID()
        
        m1 = Meeting(
            id: meeting1Id,
            title: "Roadmap Sync",
            createdAt: Date().addingTimeInterval(-86400),
            duration: 1800,
            status: .completed
        )
        
        m2 = Meeting(
            id: meeting2Id,
            title: "Sprint Retrospective",
            createdAt: Date().addingTimeInterval(-3600),
            duration: 3600,
            status: .completed
        )
        
        context.insert(m1)
        context.insert(m2)
        
        let speaker1 = Speaker(name: "Sarah Connor", avatarColorHex: "#3B82F6")
        let speaker2 = Speaker(name: "Alex Rivera", avatarColorHex: "#10B981")
        let speaker3 = Speaker(name: "John Doe", avatarColorHex: "#F59E0B")
        context.insert(speaker1)
        context.insert(speaker2)
        context.insert(speaker3)
        
        // Insert sample action items
        let item1 = ActionItem(
            id: UUID(),
            title: "Finalize PRD for v2.0",
            taskDescription: "Review specs with design team",
            isCompleted: false,
            priority: .high,
            dueDate: Date().addingTimeInterval(86400 * 2), // in 2 days
            assignee: speaker1,
            meeting: m1
        )
        
        let item2 = ActionItem(
            id: UUID(),
            title: "Update API documentation",
            taskDescription: "Swagger docs for auth",
            isCompleted: false,
            priority: .medium,
            dueDate: Date().addingTimeInterval(-86400), // yesterday (overdue)
            assignee: speaker2,
            meeting: m1
        )
        
        let item3 = ActionItem(
            id: UUID(),
            title: "Deploy hotfix to staging",
            taskDescription: "Patch login crash",
            isCompleted: true,
            priority: .urgent,
            dueDate: Date().addingTimeInterval(3600),
            assignee: speaker3,
            meeting: m2
        )
        
        context.insert(item1)
        context.insert(item2)
        context.insert(item3)
        m1.actionItems = [item1, item2]
        m2.actionItems = [item3]
        try? context.save()
        
        sut = ActionItemsViewModel(
            modelContext: context,
            remindersService: mockRemindersSyncService
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        clearActionItems()
        try? context.delete(model: Meeting.self)
        try? context.delete(model: Speaker.self)
        try? context.save()
        mockRemindersSyncService = nil
        sut = nil
        context = nil
        modelContainer = nil
        m1 = nil
        m2 = nil
        try await super.tearDown()
    }
    
    // MARK: - Persistence Test Helpers
    
    private func fetchActionItem(id: UUID) -> ActionItem? {
        var descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func clearActionItems() {
        try? context.delete(model: ActionItem.self)
        try? context.save()
    }
    
    private func deleteMeetingAndCascade(id: UUID) {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let meeting = try? context.fetch(descriptor).first {
            context.delete(meeting)
            try? context.save()
        }
    }
    
    // MARK: - Tier 1: Feature 48 (Action Items Interactive Checklist)
    
    /// Tier 1: Feature 48 - Validates tapping checklist checkbox toggles completion status.
    func test_tier1_feature48_actionItemChecklistToggleCompleted() throws {
        sut.loadActionItems()
        let pendingItem = sut.allActionItems.first(where: { !$0.isCompleted })!
        
        XCTAssertFalse(pendingItem.isCompleted)
        
        sut.toggleCompletion(for: pendingItem)
        
        let updated = sut.allActionItems.first(where: { $0.id == pendingItem.id })
        XCTAssertTrue(updated?.isCompleted ?? false)
    }
    
    /// Tier 1: Feature 48 - Validates completed task visual representation has strikethrough flag.
    func test_tier1_feature48_actionItemStrikethroughStyleWhenCompleted() throws {
        sut.loadActionItems()
        let completedItem = sut.allActionItems.first(where: { $0.isCompleted })!
        
        XCTAssertTrue(sut.hasStrikethrough(for: completedItem))
    }
    
    /// Tier 1: Feature 48 - Validates priority badge colors match brand tokens.
    func test_tier1_feature48_priorityBadgeColorsHighMediumLow() throws {
        XCTAssertEqual(sut.badgeColorHex(for: .urgent), "#EF4444")  // Coral Red
        XCTAssertEqual(sut.badgeColorHex(for: .high), "#F59E0B")    // Warm Amber
        XCTAssertEqual(sut.badgeColorHex(for: .medium), "#3B82F6")  // Live Blue
        XCTAssertEqual(sut.badgeColorHex(for: .low), "#6B7280")     // Neutral Slate
    }
    
    /// Tier 1: Feature 48 - Validates assignee chip display text.
    func test_tier1_feature48_assigneeChipDisplay() throws {
        sut.loadActionItems()
        let item = sut.allActionItems.first(where: { $0.assigneeName == "Sarah Connor" })
        XCTAssertEqual(sut.assigneeDisplayName(for: item!), "Sarah Connor")
    }
    
    /// Tier 1: Feature 48 - Validates upcoming due date formatting string.
    func test_tier1_feature48_dueDateFormattingUpcoming() throws {
        sut.loadActionItems()
        let item = sut.allActionItems.first(where: { $0.title == "Finalize PRD for v2.0" })!
        
        let formatted = sut.formatDueDate(item.dueDate)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertFalse(sut.isOverdue(item))
    }
    
    // MARK: - Tier 1: Feature 49 (Add / Edit Action Item Sheet)
    
    /// Tier 1: Feature 49 - Validates opening add action item modal sheet initializes empty fields.
    func test_tier1_feature49_openAddActionItemSheet() throws {
        sut.openCreateSheet(forMeetingId: meeting1Id)
        
        XCTAssertTrue(sut.isShowingActionItemSheet)
        XCTAssertEqual(sut.sheetMode, .create)
        XCTAssertEqual(sut.sheetTitle, "")
        XCTAssertEqual(sut.sheetPriority, .medium)
    }
    
    /// Tier 1: Feature 49 - Validates creating new action item inserts record into data store.
    func test_tier1_feature49_createActionItemWithFullDetails() throws {
        sut.openCreateSheet(forMeetingId: meeting1Id)
        sut.sheetTitle = "Write unit tests for ViewModel"
        sut.sheetDescription = "Ensure 100% test coverage"
        sut.sheetAssignee = "Taylor Swift"
        sut.sheetPriority = .high
        let due = Date().addingTimeInterval(86400 * 3)
        sut.sheetDueDate = due
        
        let created = try sut.saveActionItem()
        
        XCTAssertNotNil(created)
        XCTAssertEqual(created.title, "Write unit tests for ViewModel")
        XCTAssertEqual(created.assigneeName, "Taylor Swift")
        XCTAssertEqual(created.priority, .high)
        XCTAssertFalse(sut.isShowingActionItemSheet)
    }
    
    /// Tier 1: Feature 49 - Validates editing existing action item updates its properties.
    func test_tier1_feature49_editActionItemUpdatesProperties() throws {
        sut.loadActionItems()
        let itemToEdit = sut.allActionItems.first!
        
        sut.openEditSheet(for: itemToEdit)
        XCTAssertEqual(sut.sheetMode, .edit)
        XCTAssertEqual(sut.sheetTitle, itemToEdit.title)
        
        sut.sheetTitle = "Updated Task Title"
        sut.sheetPriority = .urgent
        
        let updated = try sut.saveActionItem()
        XCTAssertEqual(updated.title, "Updated Task Title")
        XCTAssertEqual(updated.priority, .urgent)
    }
    
    /// Tier 1: Feature 49 - Validates deleting action item removes it from list and store.
    func test_tier1_feature49_deleteActionItemRemovesRecord() throws {
        sut.loadActionItems()
        let countBefore = sut.allActionItems.count
        let itemToDelete = sut.allActionItems.first!
        
        sut.deleteActionItem(itemToDelete)
        
        XCTAssertEqual(sut.allActionItems.count, countBefore - 1)
        XCTAssertNil(fetchActionItem(id: itemToDelete.id))
    }
    
    // MARK: - Tier 1: Feature 50 (Sync to Apple Reminders)
    
    /// Tier 1: Feature 50 - Validates syncing pending tasks dispatches EventKit sync calls.
    func test_tier1_feature50_syncToRemindersDispatchesEventKit() throws {
        sut.loadActionItems()
        
        let syncedCount = sut.syncPendingToAppleReminders()
        
        XCTAssertEqual(syncedCount, 2) // 2 pending items
        XCTAssertEqual(mockRemindersSyncService.dispatchedRemindersCount, 2)
    }
    
    /// Tier 1: Feature 50 - Validates synced status badge updates on completion.
    func test_tier1_feature50_syncStatusBadgeUpdatesOnCompletion() throws {
        sut.loadActionItems()
        _ = sut.syncPendingToAppleReminders()
        
        let pending = sut.allActionItems.filter({ !$0.isCompleted })
        for item in pending {
            XCTAssertTrue(item.reminderIdentifier != nil)
        }
    }
    
    /// Tier 1: Feature 50 - Validates created reminder list name is "MeetMind".
    func test_tier1_feature50_remindersListNameIsMeetMind() throws {
        _ = sut.syncPendingToAppleReminders()
        XCTAssertEqual(mockRemindersSyncService.targetReminderListName, "MeetMind")
    }
    
    // MARK: - Tier 1: Feature 54 (Cross-Meeting Action Console)
    
    /// Tier 1: Feature 54 - Validates cross-meeting console aggregates all tasks across all meetings.
    func test_tier1_feature54_crossMeetingConsoleAggregatesAllTasks() throws {
        sut.loadActionItems()
        
        XCTAssertEqual(sut.allActionItems.count, 3)
        XCTAssertEqual(sut.totalTaskCount, 3)
    }
    
    /// Tier 1: Feature 54 - Validates filtering by "Pending" returns only incomplete tasks.
    func test_tier1_feature54_filterPendingTasks() throws {
        sut.loadActionItems()
        sut.setFilterScope(.pending)
        
        XCTAssertEqual(sut.filteredActionItems.count, 2)
        for item in sut.filteredActionItems {
            XCTAssertFalse(item.isCompleted)
        }
    }
    
    /// Tier 1: Feature 54 - Validates filtering by "Due Soon" isolates tasks due within 48 hours.
    func test_tier1_feature54_filterDueSoonTasks() throws {
        sut.loadActionItems()
        sut.setFilterScope(.dueSoon)
        
        XCTAssertGreaterThanOrEqual(sut.filteredActionItems.count, 1)
    }
    
    /// Tier 1: Feature 54 - Validates filtering by "Completed" returns completed tasks.
    func test_tier1_feature54_filterCompletedTasks() throws {
        sut.loadActionItems()
        sut.setFilterScope(.completed)
        
        XCTAssertEqual(sut.filteredActionItems.count, 1)
        XCTAssertEqual(sut.filteredActionItems.first?.title, "Deploy hotfix to staging")
    }
    
    /// Tier 1: Feature 54 - Validates grouping tasks by priority sections (Urgent -> High -> Medium -> Low).
    func test_tier1_feature54_groupByPrioritySections() throws {
        sut.loadActionItems()
        sut.setGrouping(.priority)
        
        let sections = sut.groupedSections
        XCTAssertGreaterThanOrEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.title, "Urgent")
    }
    
    /// Tier 1: Feature 54 - Validates bulk complete marks all selected action items completed.
    func test_tier1_feature54_bulkCompleteActionItems() throws {
        sut.loadActionItems()
        let pending = sut.allActionItems.filter({ !$0.isCompleted })
        XCTAssertEqual(pending.count, 2)
        
        sut.bulkComplete(items: pending)
        
        for item in pending {
            let updated = fetchActionItem(id: item.id)
            XCTAssertTrue(updated?.isCompleted ?? false)
        }
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 48: Empty States & Overdue)
    
    /// Tier 2: Feature 48 - Validates zero action items renders empty placeholder.
    func test_tier2_feature48_zeroActionItemsEmptyState() throws {
        clearActionItems()
        sut.loadActionItems()
        
        XCTAssertTrue(sut.allActionItems.isEmpty)
        XCTAssertTrue(sut.hasEmptyActionItems)
        XCTAssertEqual(sut.emptyActionItemsPlaceholder, "No action items found.")
    }
    
    /// Tier 2: Feature 48 - Validates rapid checkbox toggling preserves final state.
    func test_tier2_feature48_rapidCheckboxTogglingMaintainsState() throws {
        sut.loadActionItems()
        let item = sut.allActionItems.first!
        let initialCompleted = item.isCompleted
        
        for _ in 0..<20 {
            sut.toggleCompletion(for: item)
        }
        
        let current = sut.allActionItems.first(where: { $0.id == item.id })
        XCTAssertEqual(current?.isCompleted, initialCompleted)
    }
    
    /// Tier 2: Feature 48 - Validates overdue due date displays red warning badge.
    func test_tier2_feature48_overdueDueDateDisplaysRedWarningBadge() throws {
        sut.loadActionItems()
        let overdueItem = sut.allActionItems.first(where: { $0.title == "Update API documentation" })!
        
        XCTAssertTrue(sut.isOverdue(overdueItem))
        XCTAssertEqual(sut.dueDateBadgeColorHex(for: overdueItem), "#EF4444")
    }
    
    /// Tier 2: Feature 48 - Validates unassigned task assignee chip displays "Unassigned".
    func test_tier2_feature48_unassignedTaskAssigneeFallback() throws {
        let unassignedItem = ActionItem(
            id: UUID(),
            title: "Task with no owner",
            taskDescription: "",
            isCompleted: false,
            priority: .low,
            dueDate: nil,
            assignee: nil,
            meeting: m1
        )
        context.insert(unassignedItem)
        try? context.save()
        
        XCTAssertEqual(sut.assigneeDisplayName(for: unassignedItem), "Unassigned")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 49: Form Validation & Cancel)
    
    /// Tier 2: Feature 49 - Validates saving blank title throws validation error.
    func test_tier2_feature49_blankTitleValidationRejection() throws {
        sut.openCreateSheet(forMeetingId: meeting1Id)
        sut.sheetTitle = ""
        
        XCTAssertFalse(sut.isSheetValid)
        XCTAssertThrowsError(try sut.saveActionItem()) { error in
            XCTAssertTrue(error is ActionItemValidationError)
        }
    }
    
    /// Tier 2: Feature 49 - Validates whitespace-only title is rejected as invalid.
    func test_tier2_feature49_whitespaceOnlyTitleRejected() throws {
        sut.openCreateSheet(forMeetingId: meeting1Id)
        sut.sheetTitle = "   \t \n "
        
        XCTAssertFalse(sut.isSheetValid)
    }
    
    /// Tier 2: Feature 49 - Validates due date in past is allowed with warning banner.
    func test_tier2_feature49_pastDueDateAllowedWithWarning() throws {
        sut.openCreateSheet(forMeetingId: meeting1Id)
        sut.sheetTitle = "Retrospective Action"
        sut.sheetDueDate = Date().addingTimeInterval(-86400 * 5)
        
        XCTAssertTrue(sut.hasPastDueDateWarning)
        XCTAssertEqual(sut.pastDueDateWarningMessage, "Selected due date is in the past.")
        XCTAssertTrue(sut.isSheetValid) // Can still save
    }
    
    /// Tier 2: Feature 49 - Validates dismissing modal sheet without saving cancels changes.
    func test_tier2_feature49_cancelSheetDiscardsDraftWithoutSaving() throws {
        sut.loadActionItems()
        let countBefore = sut.allActionItems.count
        
        sut.openCreateSheet(forMeetingId: meeting1Id)
        sut.sheetTitle = "Discarded Draft"
        sut.cancelSheet()
        
        XCTAssertFalse(sut.isShowingActionItemSheet)
        XCTAssertEqual(sut.allActionItems.count, countBefore)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 50: Reminders Error Fallbacks)
    
    /// Tier 2: Feature 50 - Validates reminders permission denied displays instructional primer.
    func test_tier2_feature50_remindersPermissionDeniedShowsPrimer() throws {
        mockRemindersSyncService.isAuthorized = false
        sut.loadActionItems()
        
        let count = sut.syncPendingToAppleReminders()
        
        XCTAssertEqual(count, 0)
        XCTAssertTrue(sut.isShowingRemindersPermissionAlert)
        XCTAssertEqual(sut.remindersAlertMessage, "Reminders access is required to sync action items.")
    }
    
    /// Tier 2: Feature 50 - Validates syncing with zero pending tasks presents "Nothing to sync" banner.
    func test_tier2_feature50_syncZeroTasksAlertsNothingToSync() throws {
        clearActionItems()
        sut.loadActionItems()
        
        let count = sut.syncPendingToAppleReminders()
        
        XCTAssertEqual(count, 0)
        XCTAssertTrue(sut.isShowingNothingToSyncBanner)
    }
    
    /// Tier 2: Feature 50 - Validates repeated sync requests prevent creating duplicate reminders.
    func test_tier2_feature50_duplicateSyncPreventionAvoidsDoubleEntries() throws {
        sut.loadActionItems()
        
        let firstSyncCount = sut.syncPendingToAppleReminders()
        XCTAssertEqual(firstSyncCount, 2)
        
        // Immediate second sync should sync 0 because both are already synced
        let secondSyncCount = sut.syncPendingToAppleReminders()
        XCTAssertEqual(secondSyncCount, 0)
    }
    
    /// Tier 2: Feature 50 - Validates offline sync queues items into local sync queue.
    func test_tier2_feature50_offlineRemindersSyncQueuesForReconnection() throws {
        mockRemindersSyncService.isOnline = false
        sut.loadActionItems()
        
        _ = sut.syncPendingToAppleReminders()
        
        XCTAssertEqual(sut.pendingOfflineSyncCount, 2)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 54: Scale & Navigation Deep Links)
    
    /// Tier 2: Feature 54 - Validates performance filtering across 1,000 tasks under 150ms.
    func test_tier2_feature54_thousandTasksPerformanceFiltering() throws {
        for i in 0..<1000 {
            let item = ActionItem(
                id: UUID(),
                title: "Task #\(i)",
                taskDescription: "",
                isCompleted: i % 2 == 0,
                priority: .medium,
                dueDate: Date().addingTimeInterval(TimeInterval(i * 3600)),
                assignee: Speaker(name: "User \(i % 5)"),
                meeting: m1
            )
            context.insert(item)
        }
        try? context.save()
        sut.loadActionItems()
        
        let start = Date()
        sut.setFilterScope(.pending)
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 0.15)
        XCTAssertEqual(sut.filteredActionItems.count, 500)
    }
    
    /// Tier 2: Feature 54 - Validates deleting meeting cascades and removes its tasks from console.
    func test_tier2_feature54_deletingMeetingCascadesAndRemovesTasksFromConsole() throws {
        sut.loadActionItems()
        XCTAssertEqual(sut.allActionItems.count, 3)
        
        deleteMeetingAndCascade(id: meeting1Id)
        sut.loadActionItems()
        
        // Meeting 1 had 2 tasks, meeting 2 had 1 task -> 1 remains
        XCTAssertEqual(sut.allActionItems.count, 1)
        XCTAssertEqual(sut.allActionItems.first?.meeting?.id, meeting2Id)
    }
    
    /// Tier 2: Feature 54 - Validates tapping task generates deep link destination to source meeting.
    func test_tier2_feature54_tappingTaskDeepLinksToSourceMeeting() throws {
        sut.loadActionItems()
        let item = sut.allActionItems.first!
        
        let destination = sut.destinationForTask(item)
        XCTAssertEqual(destination, .meetingDetail(id: item.meeting?.id ?? UUID()))
    }
    
    /// Tier 2: Feature 54 - Validates grouping by due date partitions into Overdue, Today, and Upcoming.
    func test_tier2_feature54_groupByDueDateSectionsOverdueTodayUpcoming() throws {
        sut.loadActionItems()
        sut.setGrouping(.dueDate)
        
        let sectionTitles = sut.groupedSections.map { $0.title }
        XCTAssertTrue(sectionTitles.contains("Overdue"))
        XCTAssertTrue(sectionTitles.contains("Upcoming"))
    }
    
    /// Tier 2: Feature 54 - Validates bulk complete with empty selection is a safe no-op.
    func test_tier2_feature54_bulkCompleteWithEmptySelectionNoOp() throws {
        sut.bulkComplete(items: [])
        XCTAssertEqual(sut.allActionItems.count, 3)
    }
}
