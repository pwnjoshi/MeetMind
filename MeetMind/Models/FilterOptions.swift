import Foundation

// MARK: - Meeting Filter Options
public enum MeetingFilter: String, Codable, CaseIterable, Sendable {
    case all = "all"
    case today = "today"
    case thisWeek = "thisWeek"
    case hasActionItems = "hasActionItems"
    case starred = "starred"
    
    public var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .hasActionItems: return "Action Items"
        case .starred: return "Starred"
        }
    }
    
    public var iconName: String {
        switch self {
        case .all: return "tray.full"
        case .today: return "calendar.day.timeline.leading"
        case .thisWeek: return "calendar"
        case .hasActionItems: return "checklist"
        case .starred: return "star.fill"
        }
    }
    
    /// Evaluates if a meeting matches this filter in memory
    public func matches(meeting: Meeting, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            let targetDate = meeting.scheduledStartTime ?? meeting.createdAt
            return calendar.isDateInToday(targetDate)
        case .thisWeek:
            let targetDate = meeting.scheduledStartTime ?? meeting.createdAt
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return weekInterval.contains(targetDate)
        case .hasActionItems:
            return !meeting.actionItems.isEmpty
        case .starred:
            return meeting.isFavorite
        }
    }
}

// MARK: - Action Item Filter Options
public enum ActionItemFilter: String, Codable, CaseIterable, Sendable {
    case all = "all"
    case pending = "pending"
    case completed = "completed"
    case urgent = "urgent"
    
    public var title: String {
        switch self {
        case .all: return "All"
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .urgent: return "Urgent"
        }
    }
    
    public func matches(actionItem: ActionItem) -> Bool {
        switch self {
        case .all: return true
        case .pending: return !actionItem.isCompleted
        case .completed: return actionItem.isCompleted
        case .urgent: return !actionItem.isCompleted && (actionItem.priority == .urgent || actionItem.priority == .high)
        }
    }
}

// MARK: - Search Scope Options
public enum SearchScope: String, Codable, CaseIterable, Sendable {
    case all = "all"
    case titles = "titles"
    case transcripts = "transcripts"
    case summaries = "summaries"
    case actionItems = "actionItems"
    case notes = "notes"
    
    public var title: String {
        switch self {
        case .all: return "All"
        case .titles: return "Meeting Titles"
        case .transcripts: return "Transcripts"
        case .summaries: return "Summaries"
        case .actionItems: return "Action Items"
        case .notes: return "Notes"
        }
    }
}
