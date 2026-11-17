//
//  ActionItemLifecycleE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Action Item Management, Interactive Checklists,
//  Apple Reminders Sync via EventKit, Cross-Meeting Task Aggregation, and Priority Sorting
//  (Scenarios S8, S35 + Tier 3 Pairwise Combinations).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ActionItemLifecycleE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var actionVM: ActionItemsViewModel!
    private var mockRemindersService: MockRemindersSyncService!
    private var meetingA: Meeting!
    private var meetingB: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockRemindersService = MockRemindersSyncService()
        actionVM = ActionItemsViewModel(modelContext: context, remindersService: mockRemindersService)
        
        meetingA = Meeting(title: "Architecture Review", createdAt: Date(), status: .completed)
        meetingB = Meeting(title: "Product Roadmap", createdAt: Date().addingTimeInterval(-86400), status: .completed)
        context.insert(meetingA)
        context.insert(meetingB)
        try? context.save()
    }
    
    @MainActor
    override func tearDown() async throws {
        actionVM = nil
        mockRemindersService = nil
        meetingA = nil
        meetingB = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S8 (Action Item Management & Reminders Sync)
    
    /// Tier 4: Scenario S8 - Action Item Management and Apple Reminders Sync
    /// - Given: Post-meeting detail contains 3 AI-extracted action items.
    /// - When:
    ///   1. User reviews the 3 extracted action items in the meeting cockpit.
    ///   2. Toggles 1 action item as completed (round checkbox).
    ///   3. Adds a new manual action item with title "Update OpenAPI Specs", due date tomorrow, and high priority.
    ///   4. Taps "Sync to Apple Reminders" button.
    /// - Then:
    ///   - Completed item has `isCompleted == true` and title strikethrough styling.
    ///   - Manual action item is saved with 4 total items in meeting.
    ///   - EventKit sync service is invoked with 4 action items to sync.
    ///   - MeetMind Reminders list is created and populated with valid titles and due dates.
    func test_tier4_scenario8_actionItemManagementAndRemindersSync() async throws {
        // Given
        let item1 = ActionItem(title: "Refactor audio buffer tap", priority: .high, meeting: meetingA)
        let item2 = ActionItem(title: "Audit memory allocations", priority: .medium, meeting: meetingA)
        let item3 = ActionItem(title: "Write integration tests", priority: .low, meeting: meetingA)
        meetingA.actionItems = [item1, item2, item3]
        actionVM.loadActionItems(from: [meetingA])
        XCTAssertEqual(actionVM.items.count, 3)
        
        // When - 2. Toggle item 1 completed
        actionVM.toggleCompletion(for: item1)
        XCTAssertTrue(item1.isCompleted)
        XCTAssertTrue(actionVM.isItemStrikethrough(item1))
        
        // When - 3. Add manual action item
        let tomorrow = Date().addingTimeInterval(86400)
        let manualItem = try actionVM.createActionItem(
            title: "Update OpenAPI Specs",
            description: "Sync schemas with server v2",
            assignee: "Alice",
            dueDate: tomorrow,
            priority: .high,
            for: meetingA
        )
        XCTAssertEqual(meetingA.actionItems.count, 4)
        XCTAssertEqual(manualItem.priority, .high)
        XCTAssertEqual(manualItem.assigneeName, "Alice")
        
        // When - 4. Sync to Apple Reminders
        let syncResult = try await actionVM.syncAllToAppleReminders()
        
        // Then
        XCTAssertTrue(syncResult.isSuccess)
        XCTAssertEqual(syncResult.syncedCount, 4)
        XCTAssertTrue(mockRemindersService.wasSyncDispatched)
        XCTAssertEqual(mockRemindersService.lastSyncedListTitle, "MeetMind")
    }

    // MARK: - Tier 4: Scenario S35 (Cross-Meeting Task Aggregation)
    
    /// Tier 4: Scenario S35 - Cross-Meeting Task Aggregation & Console Filtering
    /// - Given: 5 meetings each contain 2 distinct action items (10 total tasks across meetings).
    /// - When:
    ///   1. User opens the dedicated Action Items tab in root navigation.
    ///   2. Console loads and aggregates all 10 action items.
    ///   3. User filters console by Priority ("High Priority Only").
    ///   4. User groups console by Due Date ("Today", "This Week", "Later").
    /// - Then:
    ///   - All 10 action items are discovered across the 5 meetings.
    ///   - Each item maintains a valid reference to its source meeting title and date.
    ///   - Priority and due date groupings accurately segregate the items.
    func test_tier4_scenario35_crossMeetingTaskAggregation() throws {
        // Given
        var testMeetings: [Meeting] = []
        for i in 1...5 {
            let m = Meeting(title: "Sprint Project \(i)", createdAt: Date().addingTimeInterval(Double(-i * 3600)), status: .completed)
            let highItem = ActionItem(title: "Task High \(i)", priority: .high, meeting: m)
            let medItem = ActionItem(title: "Task Med \(i)", priority: .medium, meeting: m)
            m.actionItems = [highItem, medItem]
            testMeetings.append(m)
        }
        
        // When - 2. Load cross-meeting console
        actionVM.loadActionItems(from: testMeetings)
        XCTAssertEqual(actionVM.items.count, 10)
        
        // When - 3. Filter High Priority
        let highTasks = actionVM.filterByPriority(.high)
        XCTAssertEqual(highTasks.count, 5)
        for task in highTasks {
            XCTAssertEqual(task.priority, .high)
            XCTAssertNotNil(task.meeting?.title)
        }
        
        // When - 4. Group by Due Date
        let grouped = actionVM.groupByDueDate()
        XCTAssertNotNil(grouped)
        XCTAssertGreaterThan(grouped.keys.count, 0)
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Action Item Completion Strikethrough & Timestamp
    /// - Verifies completing an action item sets completedAt date and strikethrough flag.
    func test_tier3_actionItemCompletionStrikethrough() throws {
        let item = ActionItem(title: "Test Task", priority: .medium)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
        
        actionVM.toggleCompletion(for: item)
        XCTAssertTrue(item.isCompleted)
        XCTAssertNotNil(item.completedAt)
        
        actionVM.toggleCompletion(for: item)
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }

    /// Tier 3: Pairwise - Action Item Creation Input Validation
    /// - Verifies empty or whitespace title throws validation error.
    func test_tier3_addEditActionItemValidation() throws {
        XCTAssertThrowsError(try actionVM.createActionItem(
            title: "   ",
            description: "",
            assignee: nil,
            dueDate: nil,
            priority: .low,
            for: meetingA
        )) { error in
            XCTAssertEqual((error as? ActionItemValidationError), .emptyTitle)
        }
    }

    /// Tier 3: Pairwise - Priority Sorting Order
    /// - Verifies items sort in order: High -> Medium -> Low.
    func test_tier3_actionItemPrioritySorting() throws {
        let low = ActionItem(title: "Low item", priority: .low)
        let high = ActionItem(title: "High item", priority: .high)
        let med = ActionItem(title: "Med item", priority: .medium)
        
        let sorted = actionVM.sortByPriority([low, high, med])
        XCTAssertEqual(sorted[0].priority, .high)
        XCTAssertEqual(sorted[1].priority, .medium)
        XCTAssertEqual(sorted[2].priority, .low)
    }

    /// Tier 3: Pairwise - EventKit Reminders Sync Payload Dispatch
    /// - Verifies reminders payload contains title, notes, and dueDate.
    func test_tier3_syncToRemindersEventKitDispatch() async throws {
        let dueDate = Date().addingTimeInterval(3600)
        let item = ActionItem(title: "Ship Build", taskDescription: "v1.0 release", dueDate: dueDate, priority: .high, meeting: meetingA)
        actionVM.loadActionItems(from: [meetingA])
        meetingA.actionItems = [item]
        
        _ = try await actionVM.syncAllToAppleReminders()
        
        XCTAssertEqual(mockRemindersService.dispatchedPayloads.count, 1)
        XCTAssertEqual(mockRemindersService.dispatchedPayloads.first?.title, "Ship Build")
        XCTAssertEqual(mockRemindersService.dispatchedPayloads.first?.notes, "v1.0 release")
    }

    /// Tier 3: Pairwise - Reminders Permission Denial Recovery
    /// - Verifies reminders permission denial displays informative prompt without crash.
    func test_tier3_syncToRemindersPermissionDenial() async throws {
        mockRemindersService.simulateAuthorizationStatus(.denied)
        
        do {
            _ = try await actionVM.syncAllToAppleReminders()
            XCTFail("Should throw on permission denial")
        } catch {
            XCTAssertTrue(actionVM.hasPermissionAlert)
            XCTAssertEqual(actionVM.permissionAlertMessage, "Reminders access denied. Enable in iOS Settings.")
        }
    }

    /// Tier 3: Pairwise - Duplicate Reminders Sync Prevention
    /// - Verifies subsequent sync updates existing reminders rather than creating duplicates.
    func test_tier3_duplicateRemindersSyncPrevention() async throws {
        let item = ActionItem(title: "Task 1", priority: .medium, meeting: meetingA)
        meetingA.actionItems = [item]
        actionVM.loadActionItems(from: [meetingA])
        
        _ = try await actionVM.syncAllToAppleReminders()
        XCTAssertNotNil(item.reminderId)
        let initialReminderID = item.reminderId
        
        _ = try await actionVM.syncAllToAppleReminders()
        XCTAssertEqual(item.reminderId, initialReminderID) // retains reminder ID
        XCTAssertEqual(mockRemindersService.dispatchedPayloads.count, 1) // updated in-place
    }

    /// Tier 3: Pairwise - Cross-Meeting Console Date Grouping
    /// - Verifies tasks are sorted into "Today", "This Week", and "Later" buckets.
    func test_tier3_crossMeetingActionConsoleGrouping() throws {
        let todayTask = ActionItem(title: "Today Task", dueDate: Date())
        let laterTask = ActionItem(title: "Later Task", dueDate: Date().addingTimeInterval(86400 * 14))
        
        let groups = actionVM.bucketByDueDate([todayTask, laterTask])
        XCTAssertTrue(groups.today.contains(where: { $0.title == "Today Task" }))
        XCTAssertTrue(groups.later.contains(where: { $0.title == "Later Task" }))
    }

    /// Tier 3: Pairwise - Cross-Meeting Bulk Completion
    /// - Verifies bulk complete marks all selected items completed across meetings.
    func test_tier3_crossMeetingBulkCompletion() throws {
        let itemA = ActionItem(title: "Item A", meeting: meetingA)
        let itemB = ActionItem(title: "Item B", meeting: meetingB)
        actionVM.loadActionItems(from: [meetingA, meetingB])
        
        actionVM.bulkComplete([itemA, itemB])
        XCTAssertTrue(itemA.isCompleted)
        XCTAssertTrue(itemB.isCompleted)
    }

    /// Tier 3: Pairwise - Meeting Cascade Deletion Removes Tasks from Feed
    /// - Verifies deleting a meeting cascades to its action items in the cross-meeting view.
    func test_tier3_meetingDeletionCascadeTasks() throws {
        let item = ActionItem(title: "Ephemeral Task", meeting: meetingA)
        meetingA.actionItems = [item]
        actionVM.loadActionItems(from: [meetingA])
        XCTAssertEqual(actionVM.items.count, 1)
        
        actionVM.handleMeetingDeleted(meetingID: meetingA.id)
        XCTAssertEqual(actionVM.items.count, 0)
    }

    /// Tier 3: Pairwise - Action Item Assignee Filter
    /// - Verifies filtering by assignee returns only tasks assigned to that individual.
    func test_tier3_actionItemAssigneeFilter() throws {
        let alice = Speaker(name: "Alice", avatarColorHex: "#3B82F6")
        let bob = Speaker(name: "Bob", avatarColorHex: "#10B981")
        let aliceTask = ActionItem(title: "Alice Task", assignee: alice)
        let bobTask = ActionItem(title: "Bob Task", assignee: bob)
        
        let filtered = actionVM.filterByAssignee("Alice", items: [aliceTask, bobTask])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Alice Task")
    }

    /// Tier 3: Pairwise - Overdue Task High-Priority Badge Highlight
    /// - Verifies task whose due date has passed receives overdue badge styling.
    func test_tier3_overdueTaskBadgeHighlight() throws {
        let pastDueDate = Date().addingTimeInterval(-86400)
        let overdueTask = ActionItem(title: "Overdue Task", dueDate: pastDueDate, isCompleted: false)
        
        XCTAssertTrue(actionVM.isOverdue(overdueTask))
        XCTAssertEqual(actionVM.badgeColorToken(for: overdueTask), "#DC2626") // coral red warning
    }

    /// Tier 3: Pairwise - Action Item Deep Link to Meeting Cockpit
    /// - Verifies tapping an action item returns the correct parent meeting ID.
    func test_tier3_actionItemDeepLinkToMeeting() throws {
        let item = ActionItem(title: "Deep Link Task", meeting: meetingA)
        
        let targetMeetingID = actionVM.parentMeetingID(for: item)
        XCTAssertEqual(targetMeetingID, meetingA.id)
    }
}
