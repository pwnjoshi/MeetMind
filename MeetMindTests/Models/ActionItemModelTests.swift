//
//  ActionItemModelTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying ActionItem model schema, priority enums,
//  completion toggle mechanics, overdue logic, and reminder sync identifiers.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ActionItemModelTests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
            Speaker.self,
            Summary.self,
            ActionItem.self,
            Note.self,
            Tag.self,
            Folder.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(modelContainer)
    }
    
    override func tearDown() async throws {
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 1, Feature 48: Action Item Models)
    
    /// Tier 1: Feature 1 - Validates default initialization values.
    func test_tier1_feature1_actionItemDefaultInitialization() throws {
        let item = ActionItem(title: "Review PR #42")
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.title, "Review PR #42")
        XCTAssertEqual(item.taskDescription, "")
        XCTAssertFalse(item.isCompleted)
        XCTAssertEqual(item.priority, .medium)
        XCTAssertNil(item.dueDate)
        XCTAssertNil(item.completedAt)
        XCTAssertNil(item.assignee)
        XCTAssertNil(item.reminderIdentifier)
        XCTAssertNil(item.meeting)
    }
    
    /// Tier 1: Feature 1 - Validates custom initialization with full parameters.
    func test_tier1_feature1_actionItemCustomInitialization() throws {
        let customID = UUID()
        let dueDate = Date(timeIntervalSince1970: 1700500000)
        let completedDate = Date(timeIntervalSince1970: 1700510000)
        let speaker = Speaker(name: "Sarah Connor", email: "sarah@resistance.org")
        
        let item = ActionItem(
            id: customID,
            title: "Submit Architecture Diagram",
            taskDescription: "Export SVG from Figma and attach to PR",
            isCompleted: true,
            priority: .high,
            dueDate: dueDate,
            completedAt: completedDate,
            assignee: speaker,
            reminderIdentifier: "EK-REM-1002"
        )
        
        XCTAssertEqual(item.id, customID)
        XCTAssertEqual(item.title, "Submit Architecture Diagram")
        XCTAssertEqual(item.taskDescription, "Export SVG from Figma and attach to PR")
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.dueDate, dueDate)
        XCTAssertEqual(item.completedAt, completedDate)
        XCTAssertEqual(item.assignee?.name, "Sarah Connor")
        XCTAssertEqual(item.reminderIdentifier, "EK-REM-1002")
    }
    
    /// Tier 1: Feature 1 - Validates persistence in memory ModelContext.
    func test_tier1_feature1_actionItemPersistenceInContext() throws {
        let item = ActionItem(title: "Write XCTest suites")
        context.insert(item)
        try context.save()
        
        let descriptor = FetchDescriptor<ActionItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Write XCTest suites")
    }
    
    /// Tier 1: Feature 48 - Validates toggleCompleted sets completed state and timestamp.
    func test_tier1_feature48_toggleCompletedSetsTimestamp() throws {
        let item = ActionItem(title: "Check CI status")
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
        
        item.toggleCompleted()
        XCTAssertTrue(item.isCompleted)
        XCTAssertNotNil(item.completedAt)
        
        // Toggle back
        item.toggleCompleted()
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }
    
    /// Tier 1: Feature 48 - Validates isOverdue logic for past due dates.
    func test_tier1_feature48_isOverdueLogic() throws {
        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)
        
        let overdueItem = ActionItem(title: "Past Due", dueDate: yesterday)
        XCTAssertTrue(overdueItem.isOverdue)
        
        let upcomingItem = ActionItem(title: "Future", dueDate: tomorrow)
        XCTAssertFalse(upcomingItem.isOverdue)
        
        let noDueDateItem = ActionItem(title: "No Due Date")
        XCTAssertFalse(noDueDateItem.isOverdue)
        
        // Completed items are NEVER overdue even if dueDate is past
        overdueItem.isCompleted = true
        XCTAssertFalse(overdueItem.isOverdue)
    }
    
    /// Tier 1: Feature 48 - Validates formattedDueDate returns valid localized string or nil.
    func test_tier1_feature48_formattedDueDateOutput() throws {
        let itemWithDate = ActionItem(title: "Dated Task", dueDate: Date(timeIntervalSince1970: 1700000000))
        XCTAssertNotNil(itemWithDate.formattedDueDate)
        XCTAssertFalse(itemWithDate.formattedDueDate!.isEmpty)
        
        let itemWithoutDate = ActionItem(title: "Undated Task")
        XCTAssertNil(itemWithoutDate.formattedDueDate)
    }
    
    /// Tier 1: Feature 48 - Validates assigneeName computed property.
    func test_tier1_feature48_assigneeNameProperty() throws {
        let speaker = Speaker(name: "John Connor")
        let assignedItem = ActionItem(title: "Lead Sprint", assignee: speaker)
        XCTAssertEqual(assignedItem.assigneeName, "John Connor")
        
        let unassignedItem = ActionItem(title: "TBD Task")
        XCTAssertEqual(unassignedItem.assigneeName, "Unassigned")
    }
    
    // MARK: - ActionPriority Enum Tests
    
    /// Tier 1: ActionPriority - Validates all cases and display names.
    func test_tier1_actionPriorityDisplayNames() throws {
        XCTAssertEqual(ActionPriority.low.displayName, "Low")
        XCTAssertEqual(ActionPriority.medium.displayName, "Medium")
        XCTAssertEqual(ActionPriority.high.displayName, "High")
        XCTAssertEqual(ActionPriority.urgent.displayName, "Urgent")
    }
    
    /// Tier 1: ActionPriority - Validates badge color tokens.
    func test_tier1_actionPriorityBadgeColors() throws {
        XCTAssertEqual(ActionPriority.low.badgeColorHex, "#6B7280")
        XCTAssertEqual(ActionPriority.medium.badgeColorHex, "#3B82F6")
        XCTAssertEqual(ActionPriority.high.badgeColorHex, "#F59E0B")
        XCTAssertEqual(ActionPriority.urgent.badgeColorHex, "#EF4444")
    }
    
    /// Tier 1: ActionPriority - Validates icon name mappings.
    func test_tier1_actionPriorityIcons() throws {
        XCTAssertEqual(ActionPriority.low.iconName, "arrow.down")
        XCTAssertEqual(ActionPriority.medium.iconName, "equal")
        XCTAssertEqual(ActionPriority.high.iconName, "arrow.up")
        XCTAssertEqual(ActionPriority.urgent.iconName, "exclamationmark.3")
    }
    
    /// Tier 1: ActionPriority - Validates comparable sorting order.
    func test_tier1_actionPriorityComparableOrder() throws {
        XCTAssertTrue(ActionPriority.low < ActionPriority.medium)
        XCTAssertTrue(ActionPriority.medium < ActionPriority.high)
        XCTAssertTrue(ActionPriority.high < ActionPriority.urgent)
        
        let unsorted: [ActionPriority] = [.urgent, .low, .high, .medium]
        let sorted = unsorted.sorted()
        XCTAssertEqual(sorted, [.low, .medium, .high, .urgent])
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    /// Tier 2: Feature 1 - Validates empty title and description.
    func test_tier2_feature1_emptyTitleAndDescription() throws {
        let item = ActionItem(title: "", taskDescription: "")
        XCTAssertEqual(item.title, "")
        XCTAssertEqual(item.taskDescription, "")
        context.insert(item)
        XCTAssertNoThrow(try context.save())
    }
    
    /// Tier 2: Feature 1 - Validates very long title and description (5,000 characters).
    func test_tier2_feature1_extremelyLongTaskDetails() throws {
        let massiveTitle = String(repeating: "Action Item Task Title ", count: 200)
        let massiveDesc = String(repeating: "Action Item Description Paragraph ", count: 200)
        let item = ActionItem(title: massiveTitle, taskDescription: massiveDesc)
        context.insert(item)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(fetched.first?.title.count, massiveTitle.count)
        XCTAssertEqual(fetched.first?.taskDescription.count, massiveDesc.count)
    }
    
    /// Tier 2: Feature 1 - Validates unrecognized priority raw value fallback to medium.
    func test_tier2_feature1_invalidPriorityRawFallback() throws {
        let item = ActionItem(title: "Fallback Priority")
        item.priorityRaw = "ultra_mega_urgent"
        XCTAssertEqual(item.priority, .medium)
    }
    
    /// Tier 2: Feature 1 - Validates distant future due date (year 2050).
    func test_tier2_feature1_distantFutureDueDate() throws {
        let future = Date(timeIntervalSince1970: 2524608000) // Year 2050
        let item = ActionItem(title: "Future Milestone", dueDate: future)
        XCTAssertFalse(item.isOverdue)
        XCTAssertNotNil(item.formattedDueDate)
    }
    
    /// Tier 2: Feature 1 - Validates multiple rapid completion toggles.
    func test_tier2_feature1_multipleRapidCompletionToggles() throws {
        let item = ActionItem(title: "Rapid Toggle")
        for _ in 0..<50 {
            item.toggleCompleted()
        }
        XCTAssertFalse(item.isCompleted)
        XCTAssertNil(item.completedAt)
    }
    
    /// Tier 2: Feature 1 - Validates special symbols, emojis, and quotes in title.
    func test_tier2_feature1_specialCharactersInTitle() throws {
        let specialTitle = "🛠️ Deploy 'v2.1.0' -> Prod (urgent!) & verify: <db_sync>"
        let item = ActionItem(title: specialTitle)
        XCTAssertEqual(item.title, specialTitle)
        context.insert(item)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(fetched.first?.title, specialTitle)
    }
    
    // MARK: - Feature 50: Reminder Sync Integration
    
    /// Tier 1: Feature 50 - Validates reminder identifier persistence.
    func test_tier1_feature50_reminderIdentifierStorage() throws {
        let item = ActionItem(title: "Sync with Reminders")
        item.reminderIdentifier = "REM-UUID-778899"
        XCTAssertEqual(item.reminderIdentifier, "REM-UUID-778899")
        
        context.insert(item)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(fetched.first?.reminderIdentifier, "REM-UUID-778899")
    }
    
    /// Tier 1: Feature 50 - Validates clearing reminder identifier.
    func test_tier1_feature50_clearReminderIdentifier() throws {
        let item = ActionItem(title: "Unlinked Task", reminderIdentifier: "REM-OLD")
        item.reminderIdentifier = nil
        XCTAssertNil(item.reminderIdentifier)
    }
    
    // MARK: - Tier 3: Pairwise Relationships & Filter Logic
    
    /// Tier 3: Pairwise - Verifies bidirectional association with Meeting.
    func test_tier3_meetingActionItemBidirectionalLink() throws {
        let meeting = Meeting(title: "Sprint Retrospective")
        let item = ActionItem(title: "Automate regression suite")
        context.insert(meeting)
        context.insert(item)
        
        meeting.addActionItem(item)
        try context.save()
        
        XCTAssertEqual(meeting.actionItems.count, 1)
        XCTAssertEqual(item.meeting?.id, meeting.id)
    }
    
    /// Tier 3: Pairwise - Verifies bidirectional association with Speaker assignee.
    func test_tier3_speakerActionItemBidirectionalLink() throws {
        let speaker = Speaker(name: "Alex Rivera", role: "DevOps Lead")
        let item = ActionItem(title: "Configure AWS S3 bucket")
        context.insert(speaker)
        context.insert(item)
        
        item.assignee = speaker
        speaker.assignedActionItems.append(item)
        try context.save()
        
        XCTAssertEqual(item.assignee?.id, speaker.id)
        XCTAssertEqual(speaker.assignedActionItems.count, 1)
        XCTAssertEqual(speaker.assignedActionItems.first?.title, "Configure AWS S3 bucket")
    }
    
    /// Tier 3: Pairwise - Verifies deleting Speaker nullifies assignee on ActionItem without deleting it.
    func test_tier3_speakerDeletionNullifiesAssignee() throws {
        let speaker = Speaker(name: "Temporary Contractor")
        let item = ActionItem(title: "Refactor legacy module", assignee: speaker)
        context.insert(speaker)
        context.insert(item)
        try context.save()
        
        XCTAssertNotNil(item.assignee)
        
        context.delete(speaker)
        try context.save()
        
        let remainingItems = try context.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(remainingItems.count, 1)
        XCTAssertNil(remainingItems.first?.assignee)
    }
    
    /// Tier 3: Pairwise - Verifies ActionItemFilter matching logic across filter scopes.
    func test_tier3_actionItemFilterEvaluation() throws {
        let pendingItem = ActionItem(title: "Pending Item", isCompleted: false, priority: .low)
        let completedItem = ActionItem(title: "Completed Item", isCompleted: true, priority: .medium)
        let urgentItem = ActionItem(title: "Urgent Item", isCompleted: false, priority: .urgent)
        let highItem = ActionItem(title: "High Item", isCompleted: false, priority: .high)
        let completedUrgentItem = ActionItem(title: "Done Urgent", isCompleted: true, priority: .urgent)
        
        // Scope .all
        XCTAssertTrue(ActionItemFilter.all.matches(actionItem: pendingItem))
        XCTAssertTrue(ActionItemFilter.all.matches(actionItem: completedItem))
        
        // Scope .pending
        XCTAssertTrue(ActionItemFilter.pending.matches(actionItem: pendingItem))
        XCTAssertFalse(ActionItemFilter.pending.matches(actionItem: completedItem))
        
        // Scope .completed
        XCTAssertFalse(ActionItemFilter.completed.matches(actionItem: pendingItem))
        XCTAssertTrue(ActionItemFilter.completed.matches(actionItem: completedItem))
        
        // Scope .urgent (requires incomplete AND urgent/high)
        XCTAssertTrue(ActionItemFilter.urgent.matches(actionItem: urgentItem))
        XCTAssertTrue(ActionItemFilter.urgent.matches(actionItem: highItem))
        XCTAssertFalse(ActionItemFilter.urgent.matches(actionItem: pendingItem)) // low
        XCTAssertFalse(ActionItemFilter.urgent.matches(actionItem: completedUrgentItem)) // completed
    }
    
    /// Tier 1: Feature 48 - Validates initial completedAt is nil on default init.
    func test_tier1_feature48_initialCompletedAtIsNil() throws {
        let item = ActionItem(title: "Uncompleted task")
        XCTAssertNil(item.completedAt)
        XCTAssertFalse(item.isCompleted)
    }
    
    /// Tier 1: Feature 48 - Validates toggleCompleted multiple times retains latest timestamp.
    func test_tier1_feature48_toggleCompletedMultipleTimesRetainsLatestTimestamp() throws {
        let item = ActionItem(title: "Toggle task")
        item.toggleCompleted()
        let firstCompletedAt = item.completedAt
        XCTAssertNotNil(firstCompletedAt)
        
        item.toggleCompleted()
        XCTAssertNil(item.completedAt)
        
        item.toggleCompleted()
        XCTAssertNotNil(item.completedAt)
        XCTAssertTrue(item.isCompleted)
    }
    
    /// Tier 1: Feature 48 - Validates all priority enum cases represented in ActionPriority.allCases.
    func test_tier1_feature48_allPrioritiesRepresentedInAllCases() throws {
        let allCases = ActionPriority.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.low))
        XCTAssertTrue(allCases.contains(.medium))
        XCTAssertTrue(allCases.contains(.high))
        XCTAssertTrue(allCases.contains(.urgent))
    }
    
    /// Tier 2: Feature 48 - Validates multiline task description formatting.
    func test_tier2_feature48_actionItemDescriptionMultiline() throws {
        let multiline = "Step 1: Check logs\nStep 2: Restart server\nStep 3: Notify stakeholders"
        let item = ActionItem(title: "Incident Response", taskDescription: multiline)
        XCTAssertEqual(item.taskDescription, multiline)
        context.insert(item)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<ActionItem>())
        XCTAssertEqual(fetched.first?.taskDescription, multiline)
    }
    
    /// Tier 2: Feature 48 - Validates due date exactly now evaluation.
    func test_tier2_feature48_actionItemWithDueDateExactlyNow() throws {
        let now = Date()
        let item = ActionItem(title: "Immediate task", dueDate: now.addingTimeInterval(-1))
        XCTAssertTrue(item.isOverdue)
    }
    
    /// Tier 2: Feature 48 - Validates negative time interval due date overdue calculation.
    func test_tier2_feature48_actionItemWithNegativeTimeIntervalDueDate() throws {
        let pastDate = Date().addingTimeInterval(-3600 * 24 * 7) // 1 week ago
        let item = ActionItem(title: "Old task", dueDate: pastDate)
        XCTAssertTrue(item.isOverdue)
    }
    
    /// Tier 2: Feature 50 - Validates reminderIdentifier clearing and reassigning.
    func test_tier2_feature50_reminderIdentifierClearingAndReassigning() throws {
        let item = ActionItem(title: "Sync task", reminderIdentifier: "REM-001")
        XCTAssertEqual(item.reminderIdentifier, "REM-001")
        item.reminderIdentifier = nil
        XCTAssertNil(item.reminderIdentifier)
        item.reminderIdentifier = "REM-002"
        XCTAssertEqual(item.reminderIdentifier, "REM-002")
    }
    
    /// Tier 3: ActionItem cascade delete when meeting is deleted.
    func test_tier3_actionItemCascadeDeleteWhenMeetingDeleted() throws {
        let meeting = Meeting(title: "Host Meeting")
        let item = ActionItem(title: "Owned task")
        meeting.addActionItem(item)
        context.insert(meeting)
        try context.save()
        
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActionItem>()).count, 1)
        context.delete(meeting)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActionItem>()).count, 0)
    }
}


extension ActionItemModelTests {
    private func makeOfflineMeeting() throws -> Meeting {
        let meeting = Meeting(title: "Offline review", status: .completed)
        context.insert(meeting)
        let fixture = #"""
        {"sourceSignature":"test","stage":"completed","turns":[{"id":"t1","text":"Rahul will send the estimate tomorrow.","start":12,"end":16,"speaker":"Speaker 1"}],"speakers":[],"analyzedChunks":1,"analysis":[{"discussion":[],"decisions":[],"tasks":[{"title":"Send the estimate","category":"Follow-up","owner":"Rahul","deadlineText":"tomorrow","priority":null,"evidence":[{"turnID":"t1","quote":"Rahul will send the estimate tomorrow."}]}]}]}
        """#
        meeting.offlineAnalysisData = Data(fixture.utf8)
        try context.save()
        return meeting
    }

    func testOfflineSuggestionsDoNotBecomeTasksBeforeReview() throws {
        let meeting = try makeOfflineMeeting()
        XCTAssertEqual(meeting.pendingTaskSuggestions.count, 1)
        XCTAssertTrue(meeting.actionItems.isEmpty)
    }

    func testConfirmedTaskPersistsEditedFieldsAndEvidenceExactlyOnce() throws {
        let meeting = try makeOfflineMeeting()
        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        let due = Date(timeIntervalSince1970: 1800000000)
        for _ in 0..<2 {
            try meeting.reviewTask(suggestion, title: "Send revised estimate", owner: "Anika", category: "Review/Approve",
                priority: "", dueDate: due, accept: true, context: context)
        }
        XCTAssertEqual(meeting.actionItems.count, 1)
        let item = try XCTUnwrap(meeting.actionItems.first)
        XCTAssertEqual(item.title, "Send revised estimate")
        XCTAssertEqual(item.assignee?.name, "Anika")
        XCTAssertEqual(item.category, "Review/Approve")
        XCTAssertEqual(item.priorityRaw, "")
        XCTAssertEqual(item.dueDate, due)
        XCTAssertTrue(item.sourceEvidence?.contains("[00:12]") == true)
        XCTAssertTrue(meeting.pendingTaskSuggestions.isEmpty)
        let fresh = ModelContext(modelContainer)
        let saved = try XCTUnwrap(fresh.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertTrue(saved.pendingTaskSuggestions.isEmpty)
        XCTAssertEqual(saved.actionItems.first?.sourceSuggestionID, suggestion.id)
    }

    func testDiscardPersistsWithoutCreatingTaskOrOwner() throws {
        let meeting = try makeOfflineMeeting()
        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        try meeting.reviewTask(suggestion, title: "", owner: "Rahul", category: "Other",
            priority: "", dueDate: nil, accept: false, context: context)
        XCTAssertTrue(meeting.pendingTaskSuggestions.isEmpty)
        XCTAssertTrue(meeting.actionItems.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Speaker>()).isEmpty)
    }

    func testEmptyConfirmedTitleDoesNotMarkSuggestionReviewed() throws {
        let meeting = try makeOfflineMeeting()
        let suggestion = try XCTUnwrap(meeting.pendingTaskSuggestions.first)
        XCTAssertThrowsError(try meeting.reviewTask(suggestion, title: "  ", owner: "", category: "Other",
            priority: "", dueDate: nil, accept: true, context: context))
        XCTAssertEqual(meeting.pendingTaskSuggestions.count, 1)
        XCTAssertTrue(meeting.actionItems.isEmpty)
    }
}
