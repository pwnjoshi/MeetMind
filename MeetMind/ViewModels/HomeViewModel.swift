import Foundation
import SwiftData
import Observation

public typealias QuickFilter = MeetingFilter

/// Status badge configuration model
public struct MeetingBadgeConfig: Sendable, Equatable {
    public let title: String
    public let iconName: String
    public let colorHex: String
    public let isPulsing: Bool
    
    public init(title: String, iconName: String, colorHex: String, isPulsing: Bool = false) {
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.isPulsing = isPulsing
    }
}

/// Central Home & Dashboard View Model managing meetings feed, status filters, and actions
@Observable
@MainActor
public final class HomeViewModel {
    public var upcomingMeetings: [Meeting] = []
    public var recentMeetings: [Meeting] = []
    public var featuredUpcomingMeeting: Meeting? = nil
    public var selectedFilter: MeetingFilter = .all
    public var activeSwipeMeetingId: UUID? = nil
    public var searchText: String = ""
    
    public var isShowingDeleteConfirmationAlert: Bool = false
    public var pendingMeetingToDelete: Meeting? = nil
    public var deletionErrorMessage: String? = nil
    public var isShowingFolderPickerSheet: Bool = false
    public var selectedMeetingForFolder: Meeting? = nil
    
    // In-memory fallback meetings list when operating without persistent context
    private var inMemoryMeetings: [Meeting] = []
    private var modelContext: ModelContext?
    private var ownedContainer: ModelContainer?
    private var dataStore: Any?
    
    public var meetings: [Meeting] {
        var list = upcomingMeetings + recentMeetings
        for m in inMemoryMeetings {
            if !list.contains(where: { $0.id == m.id }) {
                list.append(m)
            }
        }
        return list
    }
    
    public var filteredMeetings: [Meeting] {
        let all = meetings
        return all.filter { meeting in
            let matchesFilter = selectedFilter.matches(meeting: meeting)
            if !matchesFilter { return false }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            let query = searchText.lowercased()
            let titleMatch = meeting.title.lowercased().contains(query)
            let summaryMatch = meeting.summary?.executiveSummary.lowercased().contains(query) ?? false
            return titleMatch || summaryMatch
        }
    }
    
    public var filteredUpcomingMeetings: [Meeting] {
        upcomingMeetings.filter { meeting in
            let matchesFilter = selectedFilter.matches(meeting: meeting)
            if !matchesFilter { return false }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            let query = searchText.lowercased()
            let titleMatch = meeting.title.lowercased().contains(query)
            let summaryMatch = meeting.summary?.executiveSummary.lowercased().contains(query) ?? false
            return titleMatch || summaryMatch
        }
    }
    
    public var filteredRecentMeetings: [Meeting] {
        recentMeetings.filter { meeting in
            let matchesFilter = selectedFilter.matches(meeting: meeting)
            if !matchesFilter { return false }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            let query = searchText.lowercased()
            let titleMatch = meeting.title.lowercased().contains(query)
            let summaryMatch = meeting.summary?.executiveSummary.lowercased().contains(query) ?? false
            return titleMatch || summaryMatch
        }
    }
    
    public var upcomingMeeting: Meeting? {
        featuredUpcomingMeeting ?? upcomingMeetings.first
    }
    
    public var isEmptyState: Bool {
        upcomingMeetings.isEmpty && recentMeetings.isEmpty && inMemoryMeetings.isEmpty
    }
    
    public var totalMeetingCount: Int {
        meetings.count
    }
    
    public var upcomingCount: Int {
        upcomingMeetings.count
    }
    
    public var completedCount: Int {
        recentMeetings.filter { $0.status == .completed }.count
    }
    
    public var hasEmptyFilterResults: Bool {
        filteredMeetings.isEmpty && !isEmptyState
    }
    
    public var emptyFilterMessage: String {
        "No meetings found for '\(selectedFilter.title)'"
    }
    
    public init(modelContext: ModelContext? = nil, dataStore: Any? = nil) {
        self.modelContext = modelContext
        self.dataStore = dataStore
        if modelContext == nil && dataStore == nil {
            if let container = try? ModelContainerFactory.createInMemoryContainer() {
                self.ownedContainer = container
                self.modelContext = container.mainContext
            }
        }
        fetchMeetings()
    }
    
    public func setModelContext(_ context: ModelContext?) {
        guard let context = context else { return }
        self.modelContext = context
    }
    
    public func fetchMeetings() {
        if let context = modelContext {
            let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            if let all = try? context.fetch(descriptor) {
                partitionMeetings(all)
                return
            }
        }
        
        // If dataStore was provided, attempt reflection/dynamic fetch or use existing inMemoryMeetings
        if let dataStore = dataStore {
            let mirror = Mirror(reflecting: dataStore)
            for child in mirror.children {
                if let meetingsList = child.value as? [Meeting] {
                    partitionMeetings(meetingsList)
                    return
                }
            }
        }
        
        partitionMeetings(inMemoryMeetings)
    }
    
    private func partitionMeetings(_ allMeetings: [Meeting]) {
        var combined = allMeetings
        for m in inMemoryMeetings {
            if !combined.contains(where: { $0.id == m.id }) {
                combined.append(m)
            }
        }
        
        let now = Date()
        upcomingMeetings = combined
            .filter { meeting in
                let targetDate = meeting.scheduledStartTime ?? meeting.createdAt
                return targetDate > now && meeting.status == .scheduled
            }
            .sorted { ($0.scheduledStartTime ?? $0.createdAt) < ($1.scheduledStartTime ?? $1.createdAt) }
        
        recentMeetings = combined
            .filter { meeting in
                let targetDate = meeting.scheduledStartTime ?? meeting.createdAt
                return targetDate <= now || meeting.status != .scheduled
            }
            .sorted { ($0.scheduledStartTime ?? $0.createdAt) > ($1.scheduledStartTime ?? $1.createdAt) }
        
        featuredUpcomingMeeting = upcomingMeetings.first
    }
    
    public func addMeeting(_ meeting: Meeting) {
        if let context = modelContext {
            if meeting.modelContext == nil {
                context.insert(meeting)
                try? context.save()
            }
        }
        if !inMemoryMeetings.contains(where: { $0.id == meeting.id }) {
            inMemoryMeetings.append(meeting)
        }
        fetchMeetings()
    }
    
    public func setFilter(_ filter: MeetingFilter) {
        self.selectedFilter = filter
    }
    
    public func setSearchText(_ text: String) {
        self.searchText = text
    }
    
    public func clearFiltersAndSearch() {
        self.selectedFilter = .all
        self.searchText = ""
    }
    
    public func toggleFavorite(meetingId: UUID) {
        if let meeting = meetings.first(where: { $0.id == meetingId }) {
            toggleFavorite(for: meeting)
        }
    }
    
    public func toggleFavorite(_ meeting: Meeting) {
        toggleFavorite(for: meeting)
    }
    
    public func toggleFavorite(for meeting: Meeting) {
        meeting.toggleFavorite()
        try? modelContext?.save()
        fetchMeetings()
    }
    
    public func starColorToken(for meeting: Meeting) -> String {
        meeting.isFavorite ? "#F59E0B" : "#9CA3AF"
    }
    
    public func requestDeleteConfirmation(for meeting: Meeting) {
        pendingMeetingToDelete = meeting
        isShowingDeleteConfirmationAlert = true
    }
    
    public func cancelDeleteConfirmation() {
        pendingMeetingToDelete = nil
        isShowingDeleteConfirmationAlert = false
    }
    
    public func confirmDelete() {
        guard let meeting = pendingMeetingToDelete else { return }
        pendingMeetingToDelete = nil
        isShowingDeleteConfirmationAlert = false
        Task { @MainActor in
            do { try await deleteMeeting(meeting) }
            catch { deletionErrorMessage = error.localizedDescription }
        }
    }
    
    public func confirmDeleteMeeting(_ meeting: Meeting) {
        pendingMeetingToDelete = nil
        isShowingDeleteConfirmationAlert = false
        Task { @MainActor in
            do { try await deleteMeeting(meeting) }
            catch { deletionErrorMessage = error.localizedDescription }
        }
    }
    
    public func deleteMeeting(id: UUID) async throws {
        if let meeting = meetings.first(where: { $0.id == id }) {
            try await deleteMeeting(meeting)
        }
    }
    
    public func deleteMeeting(_ meeting: Meeting) async throws {
        let id = meeting.id
        if let context = modelContext {
            _ = try await DeletionCoordinator(modelContext: context).deleteMeeting(meeting)
        }
        inMemoryMeetings.removeAll { $0.id == id }
        upcomingMeetings.removeAll { $0.id == id }
        recentMeetings.removeAll { $0.id == id }
        if featuredUpcomingMeeting?.id == id {
            featuredUpcomingMeeting = upcomingMeetings.first
        }
        fetchMeetings()
    }
    
    public func moveMeetingToFolder(meetingId: UUID, folder: Folder?) {
        if let meeting = meetings.first(where: { $0.id == meetingId }) {
            meeting.folder = folder
            if let f = folder {
                if !f.meetings.contains(where: { $0.id == meeting.id }) {
                    f.meetings.append(meeting)
                }
            }
            try? modelContext?.save()
            fetchMeetings()
        }
    }
    
    public func moveMeeting(_ meeting: Meeting, to folder: Any?) {
        if let f = folder as? Folder {
            moveMeetingToFolder(meetingId: meeting.id, folder: f)
        } else {
            if let f = meeting.folder {
                f.meetings.removeAll { $0.id == meeting.id }
            }
            meeting.folder = nil
            try? modelContext?.save()
            fetchMeetings()
        }
    }
    
    public func addTag(_ tag: Tag, to meeting: Meeting) {
        if !meeting.tags.contains(where: { $0.id == tag.id }) {
            meeting.tags.append(tag)
        }
        if !tag.meetings.contains(where: { $0.id == meeting.id }) {
            tag.meetings.append(meeting)
        }
        try? modelContext?.save()
        fetchMeetings()
    }
    
    public func removeTag(_ tag: Tag, from meeting: Meeting) {
        meeting.tags.removeAll { $0.id == tag.id }
        tag.meetings.removeAll { $0.id == meeting.id }
        try? modelContext?.save()
        fetchMeetings()
    }
    
    public func meetings(taggedWith tagName: String) -> [Meeting] {
        meetings.filter { meeting in
            meeting.tags.contains { $0.name.localizedCaseInsensitiveCompare(tagName) == .orderedSame }
        }
    }
    
    public func deleteFolder(_ folder: Folder) {
        for m in meetings where m.folder?.id == folder.id {
            m.folder = nil
        }
        folder.meetings.removeAll()
        if let context = modelContext {
            context.delete(folder)
            try? context.save()
        }
        fetchMeetings()
    }
    
    public func filterMeetings(dateRange: MeetingFilter, hasActionItems: Bool) -> [Meeting] {
        meetings.filter { meeting in
            let matchesDate = dateRange.matches(meeting: meeting)
            let matchesActionItems = hasActionItems ? !meeting.actionItems.isEmpty : true
            return matchesDate && matchesActionItems
        }
    }
    
    public func countdownText(for meeting: Meeting, referenceDate: Date = Date()) -> String {
        guard let startTime = meeting.scheduledStartTime else { return "" }
        let diff = startTime.timeIntervalSince(referenceDate)
        if diff <= 0 {
            return "Happening now"
        }
        let minutes = Int(round(diff / 60.0))
        if minutes < 60 {
            return "Starts in \(minutes) mins"
        }
        let hours = minutes / 60
        let remainingMins = minutes % 60
        if remainingMins == 0 {
            return hours == 1 ? "Starts in 1 hour" : "Starts in \(hours) hours"
        } else {
            return "Starts in \(hours)h \(remainingMins)m"
        }
    }
    
    public func transitionStatus(for meeting: Meeting, to nextStatus: MeetingStatus) {
        meeting.status = nextStatus
        try? modelContext?.save()
        fetchMeetings()
    }
    
    public func formatMeetingDuration(_ meeting: Meeting) -> String {
        if meeting.duration == 0 {
            return "0m"
        }
        let totalSeconds = Int(meeting.duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    public func generateSharePayload(for meeting: Meeting) -> String {
        var payload = "MeetMind Meeting Minutes: \(meeting.title)\nDate: \(meeting.formattedDate)\nDuration: \(meeting.formattedDuration)\n\n"
        if let summary = meeting.summary {
            payload += "Executive Summary:\n\(summary.executiveSummary)\n\n"
        }
        if !meeting.actionItems.isEmpty {
            payload += "Action Items:\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "[x]" : "[ ]"
                payload += "- \(check) \(item.title) (\(item.assigneeName))\n"
            }
        }
        return payload
    }
    
    public func badgeConfiguration(for status: MeetingStatus) -> MeetingBadgeConfig {
        switch status {
        case .scheduled:
            return MeetingBadgeConfig(title: "Scheduled", iconName: "calendar", colorHex: "#3B82F6", isPulsing: false)
        case .recording:
            return MeetingBadgeConfig(title: "Recording", iconName: "record.circle.fill", colorHex: "#EF4444", isPulsing: true)
        case .processing:
            return MeetingBadgeConfig(title: "Processing", iconName: "gearshape.arrow.triangle.2.circlepath", colorHex: "#F59E0B", isPulsing: false)
        case .completed:
            return MeetingBadgeConfig(title: "Completed", iconName: "checkmark.circle.fill", colorHex: "#10B981", isPulsing: false)
        case .archived:
            return MeetingBadgeConfig(title: "Archived", iconName: "archivebox.fill", colorHex: "#6B7280", isPulsing: false)
        }
    }
    
    public func beginSwipeGesture(for meetingId: UUID) {
        activeSwipeMeetingId = meetingId
    }
    
    public func cancelSwipeGesture() {
        activeSwipeMeetingId = nil
    }
}
