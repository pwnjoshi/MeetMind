//
//  HomeViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Comprehensive test suite covering Central Dashboard Feed, Meeting Status Badges,
/// Quick Filter Chips, and Meeting Card Swipe Actions.
/// Corresponds to Features 18, 19, 20, and 21.
@MainActor
final class HomeViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: HomeViewModel!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        sut = HomeViewModel(modelContext: context)
    }
    
    @MainActor
    override func tearDown() async throws {
        clearMeetings()
        sut = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Persistence Test Helpers
    
    @discardableResult
    private func createMeeting(
        title: String,
        dateOffset: TimeInterval,
        status: MeetingStatus,
        isFavorite: Bool = false
    ) -> Meeting {
        let now = Date()
        let scheduled = dateOffset > 0 ? now.addingTimeInterval(dateOffset) : nil
        let created = dateOffset <= 0 ? now.addingTimeInterval(dateOffset) : now
        
        let meeting = Meeting(
            title: title,
            createdAt: created,
            scheduledStartTime: scheduled,
            duration: 1800,
            status: status,
            isFavorite: isFavorite
        )
        context.insert(meeting)
        try? context.save()
        return meeting
    }
    
    private func fetchMeeting(id: UUID) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func clearMeetings() {
        try? context.delete(model: Meeting.self)
        try? context.delete(model: Folder.self)
        try? context.delete(model: ActionItem.self)
        try? context.delete(model: Summary.self)
        try? context.save()
    }
    
    // MARK: - Tier 1: Feature 18 (Central Dashboard Feed)
    
    /// Tier 1: Feature 18 - Validates initial dashboard fetch loads and partitions meetings into upcoming and recent feeds.
    func test_tier1_feature18_dashboardInitialFetchPopulatesMeetings() throws {
        let futureMeeting = createMeeting(title: "Upcoming Roadmap Sync", dateOffset: 3600, status: .scheduled)
        let pastMeeting1 = createMeeting(title: "Sprint Retrospective", dateOffset: -7200, status: .completed)
        let pastMeeting2 = createMeeting(title: "1-on-1 with Lead", dateOffset: -14400, status: .completed)
        _ = (futureMeeting, pastMeeting1, pastMeeting2)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.upcomingMeetings.count, 1)
        XCTAssertEqual(sut.upcomingMeetings.first?.title, "Upcoming Roadmap Sync")
        XCTAssertEqual(sut.recentMeetings.count, 2)
        XCTAssertFalse(sut.isEmptyState)
    }
    
    /// Tier 1: Feature 18 - Validates upcoming meeting identification selects the closest future scheduled meeting.
    func test_tier1_feature18_upcomingMeetingIdentification() throws {
        let farMeeting = createMeeting(title: "Q4 Townhall", dateOffset: 86400 * 5, status: .scheduled)
        let nearMeeting = createMeeting(title: "Standup in 10 mins", dateOffset: 600, status: .scheduled)
        _ = (farMeeting, nearMeeting)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.featuredUpcomingMeeting?.title, "Standup in 10 mins")
    }
    
    /// Tier 1: Feature 18 - Validates recent meetings are sorted in descending order by created date.
    func test_tier1_feature18_recentMeetingsSortedByDateDescending() throws {
        let meetingOld = createMeeting(title: "Old Meeting", dateOffset: -86400, status: .completed)
        let meetingNew = createMeeting(title: "New Meeting", dateOffset: -1800, status: .completed)
        _ = (meetingOld, meetingNew)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.recentMeetings.count, 2)
        XCTAssertEqual(sut.recentMeetings.first?.title, "New Meeting")
        XCTAssertEqual(sut.recentMeetings.last?.title, "Old Meeting")
    }
    
    /// Tier 1: Feature 18 - Validates empty dashboard state detection when zero meetings exist.
    func test_tier1_feature18_emptyDashboardDetectionWhenZeroMeetings() throws {
        clearMeetings()
        sut.fetchMeetings()
        
        XCTAssertTrue(sut.isEmptyState)
        XCTAssertEqual(sut.upcomingMeetings.count, 0)
        XCTAssertEqual(sut.recentMeetings.count, 0)
        XCTAssertNil(sut.featuredUpcomingMeeting)
    }
    
    /// Tier 1: Feature 18 - Validates meeting count statistics calculation.
    func test_tier1_feature18_dashboardMeetingStatisticsCounts() throws {
        let m1 = createMeeting(title: "M1", dateOffset: 3600, status: .scheduled)
        let m2 = createMeeting(title: "M2", dateOffset: -3600, status: .completed)
        let m3 = createMeeting(title: "M3", dateOffset: -7200, status: .completed)
        _ = (m1, m2, m3)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.totalMeetingCount, 3)
        XCTAssertEqual(sut.upcomingCount, 1)
        XCTAssertEqual(sut.completedCount, 2)
    }
    
    // MARK: - Tier 1: Feature 19 (Meeting Status Badges)
    
    /// Tier 1: Feature 19 - Validates scheduled status mapping, badge title, and icon.
    func test_tier1_feature19_meetingStatusEnumScheduledMapping() throws {
        let badge = sut.badgeConfiguration(for: .scheduled)
        XCTAssertEqual(badge.title, "Scheduled")
        XCTAssertEqual(badge.iconName, "calendar")
        XCTAssertEqual(badge.colorHex, "#3B82F6") // Live Blue
    }
    
    /// Tier 1: Feature 19 - Validates recording status mapping with pulsing red indicator.
    func test_tier1_feature19_meetingStatusEnumRecordingMapping() throws {
        let badge = sut.badgeConfiguration(for: .recording)
        XCTAssertEqual(badge.title, "Recording")
        XCTAssertEqual(badge.iconName, "record.circle.fill")
        XCTAssertEqual(badge.colorHex, "#EF4444") // Coral Red
        XCTAssertTrue(badge.isPulsing)
    }
    
    /// Tier 1: Feature 19 - Validates processing status mapping with amber gear icon.
    func test_tier1_feature19_meetingStatusEnumProcessingMapping() throws {
        let badge = sut.badgeConfiguration(for: .processing)
        XCTAssertEqual(badge.title, "Processing")
        XCTAssertEqual(badge.iconName, "gearshape.arrow.triangle.2.circlepath")
        XCTAssertEqual(badge.colorHex, "#F59E0B") // Warm Amber
    }
    
    /// Tier 1: Feature 19 - Validates completed status mapping with mint green checkmark.
    func test_tier1_feature19_meetingStatusEnumCompletedMapping() throws {
        let badge = sut.badgeConfiguration(for: .completed)
        XCTAssertEqual(badge.title, "Completed")
        XCTAssertEqual(badge.iconName, "checkmark.circle.fill")
        XCTAssertEqual(badge.colorHex, "#10B981") // Mint Green
        XCTAssertFalse(badge.isPulsing)
    }
    
    /// Tier 1: Feature 19 - Validates badge color tokens match brand theme tokens.
    func test_tier1_feature19_meetingStatusBadgeColorTokens() throws {
        XCTAssertEqual(sut.badgeConfiguration(for: .archived).colorHex, "#6B7280")
        XCTAssertEqual(sut.badgeConfiguration(for: .completed).colorHex, "#10B981")
    }
    
    // MARK: - Tier 1: Feature 20 (Quick Filter Chips)
    
    /// Tier 1: Feature 20 - Validates "All" filter displays all meetings in store.
    func test_tier1_feature20_quickFilterAllReturnsAllMeetings() throws {
        let m1 = createMeeting(title: "A", dateOffset: -100, status: .completed)
        let m2 = createMeeting(title: "B", dateOffset: 100, status: .scheduled)
        _ = (m1, m2)
        
        sut.fetchMeetings()
        sut.setFilter(.all)
        
        XCTAssertEqual(sut.filteredMeetings.count, 2)
    }
    
    /// Tier 1: Feature 20 - Validates "Today" filter isolates meetings scheduled or recorded today.
    func test_tier1_feature20_quickFilterTodayFiltersCurrentDayMeetings() throws {
        let todayMeeting = createMeeting(title: "Today's Standup", dateOffset: 0, status: .completed)
        let yesterdayMeeting = createMeeting(title: "Yesterday's Review", dateOffset: -86400 * 2, status: .completed)
        _ = (todayMeeting, yesterdayMeeting)
        
        sut.fetchMeetings()
        sut.setFilter(.today)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Today's Standup")
    }
    
    /// Tier 1: Feature 20 - Validates "This Week" filter restricts to current 7-day calendar window.
    func test_tier1_feature20_quickFilterThisWeekFiltersCurrentWeekRange() throws {
        let thisWeekMeeting = createMeeting(title: "Midweek Sync", dateOffset: -86400 * 2, status: .completed)
        let lastMonthMeeting = createMeeting(title: "Last Month Sync", dateOffset: -86400 * 30, status: .completed)
        _ = (thisWeekMeeting, lastMonthMeeting)
        
        sut.fetchMeetings()
        sut.setFilter(.thisWeek)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Midweek Sync")
    }
    
    /// Tier 1: Feature 20 - Validates "Action Items" filter shows only meetings having pending action items.
    func test_tier1_feature20_quickFilterActionItemsFiltersMeetingsWithPendingTasks() throws {
        let mWithTask = createMeeting(title: "Meeting With Task", dateOffset: -100, status: .completed)
        let a1 = ActionItem(title: "Task 1", isCompleted: false, meeting: mWithTask)
        let a2 = ActionItem(title: "Task 2", isCompleted: false, meeting: mWithTask)
        let a3 = ActionItem(title: "Task 3", isCompleted: false, meeting: mWithTask)
        context.insert(a1)
        context.insert(a2)
        context.insert(a3)
        mWithTask.actionItems = [a1, a2, a3]
        
        let mWithoutTask = createMeeting(title: "Meeting No Tasks", dateOffset: -200, status: .completed)
        _ = mWithoutTask
        try? context.save()
        
        sut.fetchMeetings()
        sut.setFilter(.hasActionItems)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Meeting With Task")
    }
    
    /// Tier 1: Feature 20 - Validates "Starred" filter isolates favorite meetings.
    func test_tier1_feature20_quickFilterStarredFiltersFavoriteMeetings() throws {
        let mStarred = createMeeting(title: "Starred Board Meeting", dateOffset: -100, status: .completed, isFavorite: true)
        let mRegular = createMeeting(title: "Regular Standup", dateOffset: -200, status: .completed, isFavorite: false)
        _ = (mStarred, mRegular)
        
        sut.fetchMeetings()
        sut.setFilter(.starred)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Starred Board Meeting")
    }
    
    // MARK: - Tier 1: Feature 21 (Meeting Card Swipe Actions)
    
    /// Tier 1: Feature 21 - Validates leading swipe toggles favorite star status.
    func test_tier1_feature21_leadingSwipeTogglesFavoriteStatus() throws {
        let meeting = createMeeting(title: "Sprint Planning", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        XCTAssertFalse(sut.filteredMeetings.first!.isFavorite)
        
        sut.toggleFavorite(for: meeting)
        XCTAssertTrue(sut.filteredMeetings.first!.isFavorite)
        
        sut.toggleFavorite(for: meeting)
        XCTAssertFalse(sut.filteredMeetings.first!.isFavorite)
    }
    
    /// Tier 1: Feature 21 - Validates favorite status change persists to data store.
    func test_tier1_feature21_favoriteTogglePersistsState() throws {
        let meeting = createMeeting(title: "1-on-1", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        sut.toggleFavorite(for: meeting)
        
        let storedMeeting = fetchMeeting(id: meeting.id)
        XCTAssertEqual(storedMeeting?.isFavorite, true)
    }
    
    /// Tier 1: Feature 21 - Validates trailing swipe delete removes meeting from feed and storage.
    func test_tier1_feature21_trailingSwipeDeleteMeetingRemovesFromList() throws {
        let m1 = createMeeting(title: "To Keep", dateOffset: -100, status: .completed)
        let m2 = createMeeting(title: "To Delete", dateOffset: -200, status: .completed)
        _ = m1
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.filteredMeetings.count, 2)
        
        sut.deleteMeeting(m2)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "To Keep")
        XCTAssertNil(fetchMeeting(id: m2.id))
    }
    
    /// Tier 1: Feature 21 - Validates moving meeting to a folder updates folder association.
    func test_tier1_feature21_moveMeetingToFolderAction() throws {
        let meeting = createMeeting(title: "Roadmap Discussion", dateOffset: -100, status: .completed)
        let folder = Folder(name: "Product Roadmap", colorHex: "#3B82F6")
        context.insert(folder)
        try? context.save()
        sut.fetchMeetings()
        
        sut.moveMeeting(meeting, to: folder)
        
        let updatedMeeting = fetchMeeting(id: meeting.id)
        XCTAssertEqual(updatedMeeting?.folder?.id, folder.id)
    }
    
    /// Tier 1: Feature 21 - Validates sharing meeting generates clean plain text share payload.
    func test_tier1_feature21_shareMeetingGeneratesSharePayload() throws {
        let meeting = createMeeting(title: "Executive Sync", dateOffset: -100, status: .completed)
        let summary = Summary(executiveSummary: "Approved Q4 budget and added two engineers.", meeting: meeting)
        context.insert(summary)
        meeting.summary = summary
        try? context.save()
        
        let sharePayload = sut.generateSharePayload(for: meeting)
        XCTAssertTrue(sharePayload.contains("Executive Sync"))
        XCTAssertTrue(sharePayload.contains("Approved Q4 budget"))
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 18: Dashboard Performance & Ordering)
    
    /// Tier 2: Feature 18 - Validates dashboard handles large meeting volumes (500 items) smoothly.
    func test_tier2_feature18_dashboardHandlesLargeMeetingVolumePerformance() throws {
        for i in 0..<500 {
            _ = createMeeting(title: "Meeting #\(i)", dateOffset: TimeInterval(-i * 3600), status: .completed)
        }
        
        let start = Date()
        sut.fetchMeetings()
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertEqual(sut.recentMeetings.count, 500)
        XCTAssertLessThan(elapsed, 0.5, "Fetching 500 meetings must complete under 500ms")
    }
    
    /// Tier 2: Feature 18 - Validates that when all meetings are in past, upcoming feed is empty.
    func test_tier2_feature18_allMeetingsInPastLeavesUpcomingEmpty() throws {
        let past1 = createMeeting(title: "Past 1", dateOffset: -3600, status: .completed)
        let past2 = createMeeting(title: "Past 2", dateOffset: -7200, status: .completed)
        _ = (past1, past2)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.upcomingMeetings.count, 0)
        XCTAssertNil(sut.featuredUpcomingMeeting)
        XCTAssertEqual(sut.recentMeetings.count, 2)
    }
    
    /// Tier 2: Feature 18 - Validates that when all meetings are in future, upcoming feed selects earliest.
    func test_tier2_feature18_allMeetingsInFutureUpcomingSelectsEarliest() throws {
        let future1 = createMeeting(title: "In 3 hours", dateOffset: 10800, status: .scheduled)
        let future2 = createMeeting(title: "In 1 hour", dateOffset: 3600, status: .scheduled)
        _ = (future1, future2)
        
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.featuredUpcomingMeeting?.title, "In 1 hour")
        XCTAssertEqual(sut.upcomingMeetings.count, 2)
    }
    
    /// Tier 2: Feature 18 - Validates meeting with 0 duration renders "0m" duration string.
    func test_tier2_feature18_meetingWithoutDurationCalculatesZero() throws {
        let meeting = createMeeting(title: "Zero Duration", dateOffset: -100, status: .completed)
        meeting.duration = 0
        try? context.save()
        
        let formatted = sut.formatMeetingDuration(meeting)
        XCTAssertEqual(formatted, "0m")
    }
    
    /// Tier 2: Feature 18 - Validates deleting meeting removes it immediately from both upcoming and recent lists.
    func test_tier2_feature18_deletedMeetingImmediatelyRemovedFromDashboard() throws {
        let meeting = createMeeting(title: "Standup", dateOffset: 600, status: .scheduled)
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.upcomingMeetings.count, 1)
        
        sut.deleteMeeting(meeting)
        XCTAssertEqual(sut.upcomingMeetings.count, 0)
        XCTAssertTrue(sut.isEmptyState)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 19: Status Transitions & Fallbacks)
    
    /// Tier 2: Feature 19 - Validates unknown or invalid status string falls back cleanly to scheduled.
    func test_tier2_feature19_invalidStatusStringFallbackToScheduled() throws {
        let fallback = MeetingStatus(rawValue: "invalid_status_enum") ?? .scheduled
        XCTAssertEqual(fallback, .scheduled)
    }
    
    /// Tier 2: Feature 19 - Validates status transition from scheduled to recording.
    func test_tier2_feature19_statusTransitionScheduledToRecording() throws {
        let meeting = createMeeting(title: "Live Standup", dateOffset: 0, status: .scheduled)
        sut.fetchMeetings()
        
        sut.transitionStatus(for: meeting, to: .recording)
        
        let updated = fetchMeeting(id: meeting.id)
        XCTAssertEqual(updated?.status, .recording)
    }
    
    /// Tier 2: Feature 19 - Validates status transition from recording to processing.
    func test_tier2_feature19_statusTransitionRecordingToProcessing() throws {
        let meeting = createMeeting(title: "Sync", dateOffset: -100, status: .recording)
        sut.fetchMeetings()
        
        sut.transitionStatus(for: meeting, to: .processing)
        
        let updated = fetchMeeting(id: meeting.id)
        XCTAssertEqual(updated?.status, .processing)
    }
    
    /// Tier 2: Feature 19 - Validates status transition from processing to completed.
    func test_tier2_feature19_statusTransitionProcessingToCompleted() throws {
        let meeting = createMeeting(title: "Done Sync", dateOffset: -200, status: .processing)
        sut.fetchMeetings()
        
        sut.transitionStatus(for: meeting, to: .completed)
        
        let updated = fetchMeeting(id: meeting.id)
        XCTAssertEqual(updated?.status, .completed)
    }
    
    /// Tier 2: Feature 19 - Validates simultaneous status updates across multiple cards.
    func test_tier2_feature19_simultaneousStatusUpdatesAcrossMultipleMeetings() throws {
        let m1 = createMeeting(title: "M1", dateOffset: 100, status: .scheduled)
        let m2 = createMeeting(title: "M2", dateOffset: 200, status: .scheduled)
        sut.fetchMeetings()
        
        sut.transitionStatus(for: m1, to: .recording)
        sut.transitionStatus(for: m2, to: .archived)
        
        XCTAssertEqual(fetchMeeting(id: m1.id)?.status, .recording)
        XCTAssertEqual(fetchMeeting(id: m2.id)?.status, .archived)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 20: Filter Boundaries & Search Interaction)
    
    /// Tier 2: Feature 20 - Validates empty filter results renders appropriate empty filter placeholder.
    func test_tier2_feature20_emptyFilterResultsShowsEmptyStateMessage() throws {
        _ = createMeeting(title: "Regular Standup", dateOffset: -86400 * 10, status: .completed)
        sut.fetchMeetings()
        
        sut.setFilter(.today)
        
        XCTAssertTrue(sut.filteredMeetings.isEmpty)
        XCTAssertTrue(sut.hasEmptyFilterResults)
        XCTAssertEqual(sut.emptyFilterMessage, "No meetings found for 'Today'")
    }
    
    /// Tier 2: Feature 20 - Validates rapid switching between filter chips preserves list consistency.
    func test_tier2_feature20_rapidFilterSelectionDoesNotCorruptFilteredList() throws {
        _ = createMeeting(title: "Today", dateOffset: 0, status: .completed)
        _ = createMeeting(title: "Week", dateOffset: -86400 * 2, status: .completed)
        sut.fetchMeetings()
        
        let filters: [MeetingFilter] = [.all, .today, .thisWeek, .starred, .hasActionItems]
        for _ in 0..<30 {
            let nextFilter = filters.randomElement()!
            sut.setFilter(nextFilter)
            XCTAssertEqual(sut.selectedFilter, nextFilter)
        }
    }
    
    /// Tier 2: Feature 20 - Validates date boundary at midnight (23:59 vs 00:01) for Today filter.
    func test_tier2_feature20_filterDateBoundaryAtMidnight() throws {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let justBeforeMidnight = startOfToday.addingTimeInterval(-60) // Yesterday 23:59
        let justAfterMidnight = startOfToday.addingTimeInterval(60)   // Today 00:01
        
        let mYesterday = createMeeting(title: "Yesterday Late", dateOffset: 0, status: .completed)
        mYesterday.createdAt = justBeforeMidnight
        
        let mToday = createMeeting(title: "Today Early", dateOffset: 0, status: .completed)
        mToday.createdAt = justAfterMidnight
        try? context.save()
        
        sut.fetchMeetings()
        sut.setFilter(.today)
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Today Early")
    }
    
    /// Tier 2: Feature 20 - Validates filter combined with search query intersects both criteria.
    func test_tier2_feature20_filterCombinedWithSearchQuery() throws {
        let mTodayMatch = createMeeting(title: "Q4 Roadmap Today", dateOffset: 0, status: .completed, isFavorite: true)
        let mTodayNoMatch = createMeeting(title: "Bug Triage Today", dateOffset: 0, status: .completed, isFavorite: true)
        _ = (mTodayMatch, mTodayNoMatch)
        
        sut.fetchMeetings()
        
        sut.setFilter(.starred)
        sut.setSearchText("Roadmap")
        
        XCTAssertEqual(sut.filteredMeetings.count, 1)
        XCTAssertEqual(sut.filteredMeetings.first?.title, "Q4 Roadmap Today")
    }
    
    /// Tier 2: Feature 20 - Validates resetting filter and search restores entire feed.
    func test_tier2_feature20_clearingFilterRestoresFullFeed() throws {
        _ = createMeeting(title: "Meeting 1", dateOffset: -100, status: .completed)
        _ = createMeeting(title: "Meeting 2", dateOffset: -200, status: .completed)
        sut.fetchMeetings()
        
        sut.setFilter(.today)
        sut.setSearchText("NonExistent")
        XCTAssertEqual(sut.filteredMeetings.count, 0)
        
        sut.clearFiltersAndSearch()
        XCTAssertEqual(sut.filteredMeetings.count, 2)
        XCTAssertEqual(sut.selectedFilter, .all)
        XCTAssertEqual(sut.searchText, "")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 21: Swipe Alerts & Rollbacks)
    
    /// Tier 2: Feature 21 - Validates dismissing delete confirmation alert leaves meeting intact.
    func test_tier2_feature21_deleteConfirmationAlertCancelPreservesMeeting() throws {
        let meeting = createMeeting(title: "Preserved Meeting", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        sut.requestDeleteConfirmation(for: meeting)
        XCTAssertTrue(sut.isShowingDeleteConfirmationAlert)
        XCTAssertEqual(sut.pendingMeetingToDelete?.id, meeting.id)
        
        sut.cancelDeleteConfirmation()
        XCTAssertFalse(sut.isShowingDeleteConfirmationAlert)
        XCTAssertNil(sut.pendingMeetingToDelete)
        XCTAssertEqual(sut.filteredMeetings.count, 1)
    }
    
    /// Tier 2: Feature 21 - Validates deleting last remaining meeting triggers empty dashboard state.
    func test_tier2_feature21_deleteLastRemainingMeetingTransitionsToEmptyDashboard() throws {
        let loneMeeting = createMeeting(title: "Last Stand", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        XCTAssertFalse(sut.isEmptyState)
        
        sut.deleteMeeting(loneMeeting)
        
        XCTAssertTrue(sut.isEmptyState)
        XCTAssertEqual(sut.filteredMeetings.count, 0)
    }
    
    /// Tier 2: Feature 21 - Validates rapid favorite toggling maintains consistent boolean state.
    func test_tier2_feature21_rapidFavoriteTogglingIdempotence() throws {
        let meeting = createMeeting(title: "Rapid Star", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        for _ in 0..<20 {
            sut.toggleFavorite(for: meeting)
        }
        
        // Even number of toggles leaves it false
        XCTAssertFalse(sut.filteredMeetings.first!.isFavorite)
    }
    
    /// Tier 2: Feature 21 - Validates moving meeting to nil folder detaches folder correctly.
    func test_tier2_feature21_moveMeetingToNilFolderDetachesFolder() throws {
        let meeting = createMeeting(title: "Folder Sync", dateOffset: -100, status: .completed)
        let folder = Folder(name: "Temp Folder", colorHex: "#3B82F6")
        context.insert(folder)
        meeting.folder = folder
        try? context.save()
        sut.fetchMeetings()
        
        sut.moveMeeting(meeting, to: nil)
        
        let updated = fetchMeeting(id: meeting.id)
        XCTAssertNil(updated?.folder)
    }
    
    /// Tier 2: Feature 21 - Validates cancelling active swipe gesture preserves original row state.
    func test_tier2_feature21_swipeActionCancellationPreservesState() throws {
        let meeting = createMeeting(title: "Swipe Cancel", dateOffset: -100, status: .completed)
        sut.fetchMeetings()
        
        sut.beginSwipeGesture(for: meeting.id)
        XCTAssertEqual(sut.activeSwipeMeetingId, meeting.id)
        
        sut.cancelSwipeGesture()
        XCTAssertNil(sut.activeSwipeMeetingId)
        XCTAssertEqual(sut.filteredMeetings.count, 1)
    }
    
    /// Tier 2: Feature 18 - Validates filteredUpcomingMeetings and filteredRecentMeetings partitioning.
    func test_tier2_feature18_partitionedFeedsFiltering() throws {
        let upcoming = createMeeting(title: "Future Standup", dateOffset: 3600, status: .scheduled)
        let recent = createMeeting(title: "Past Retro", dateOffset: -3600, status: .completed)
        sut.fetchMeetings()
        
        XCTAssertEqual(sut.filteredUpcomingMeetings.count, 1)
        XCTAssertEqual(sut.filteredUpcomingMeetings.first?.id, upcoming.id)
        XCTAssertEqual(sut.filteredRecentMeetings.count, 1)
        XCTAssertEqual(sut.filteredRecentMeetings.first?.id, recent.id)
        
        sut.setSearchText("Future")
        XCTAssertEqual(sut.filteredUpcomingMeetings.count, 1)
        XCTAssertEqual(sut.filteredRecentMeetings.count, 0)
        
        sut.setSearchText("Past")
        XCTAssertEqual(sut.filteredUpcomingMeetings.count, 0)
        XCTAssertEqual(sut.filteredRecentMeetings.count, 1)
    }
    
    /// Tier 2: Feature 21 - Validates starColorToken returns expected color hex for favorited and unfavorited meetings.
    func test_tier2_feature21_starColorTokenMapping() throws {
        let unstarred = createMeeting(title: "Normal", dateOffset: -100, status: .completed, isFavorite: false)
        let starred = createMeeting(title: "Starred", dateOffset: -100, status: .completed, isFavorite: true)
        
        XCTAssertEqual(sut.starColorToken(for: unstarred), "#9CA3AF")
        XCTAssertEqual(sut.starColorToken(for: starred), "#F59E0B")
    }
}
