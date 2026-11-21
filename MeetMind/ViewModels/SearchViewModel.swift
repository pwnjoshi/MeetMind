import Foundation
import SwiftData
import Observation

/// Categorization of universal search matches across meeting domain entities
public enum SearchResultCategory: String, CaseIterable, Sendable {
    case meetingTitle = "meetingTitle"
    case transcript = "transcript"
    case summary = "summary"
    case actionItem = "actionItem"
    case note = "note"
    
    public var displayName: String {
        switch self {
        case .meetingTitle: return "Meeting Title"
        case .transcript: return "Transcript"
        case .summary: return "Summary"
        case .actionItem: return "Action Item"
        case .note: return "Note"
        }
    }
}

/// Unified search match result representation
public struct SearchResultItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let category: SearchResultCategory
    public let meetingId: UUID
    public let meetingTitle: String
    public let snippet: String
    public let timecode: TimeInterval?
    public let actionItemId: UUID?
    public var highlightRange: Range<Int>?
    /// Speaker for transcript matches (nil for other categories).
    public let speakerName: String?
    /// Secondary line for action matches, e.g. meeting, assignee and due date.
    public let detail: String?
    
    public init(
        id: UUID = UUID(),
        category: SearchResultCategory,
        meetingId: UUID,
        meetingTitle: String,
        snippet: String,
        timecode: TimeInterval? = nil,
        actionItemId: UUID? = nil,
        highlightRange: Range<Int>? = nil,
        speakerName: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.category = category
        self.meetingId = meetingId
        self.meetingTitle = meetingTitle
        self.snippet = snippet
        self.timecode = timecode
        self.actionItemId = actionItemId
        self.highlightRange = highlightRange
        self.speakerName = speakerName
        self.detail = detail
    }
}

/// The four segments shown by the Search screen (Figma: All, Meetings, Transcripts, Actions).
public enum SearchPresentedScope: String, CaseIterable, Identifiable, Sendable {
    case all, meetings, transcripts, actions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .meetings: return "Meetings"
        case .transcripts: return "Transcripts"
        case .actions: return "Actions"
        }
    }

    /// Engine scope used to gather matches. Meetings gathers everything and is narrowed afterwards.
    public var engineScope: SearchScope {
        switch self {
        case .all, .meetings: return .all
        case .transcripts: return .transcripts
        case .actions: return .actionItems
        }
    }
}

public enum SearchSuggestion: String, Sendable, Equatable {
    case decisionsThisWeek
    case actionsAssignedToMe

    public var title: String {
        switch self {
        case .decisionsThisWeek: return "Decisions this week"
        case .actionsAssignedToMe: return "Actions assigned to me"
        }
    }
}

/// One meeting row in the Meetings section: a meeting matched by title, summary or notes.
public struct MeetingSearchHit: Identifiable, Sendable, Equatable {
    public var id: UUID { meetingId }
    public let meetingId: UUID
    public let title: String
    public let detail: String?
}

/// ViewModel coordinating cross-entity universal search, debouncing, highlighting, and search history
@Observable
@MainActor
public final class SearchViewModel {
    public var searchQuery: String = ""
    public var selectedScope: SearchScope = .all
    public private(set) var presentedScope: SearchPresentedScope = .all
    public var searchResults: [SearchResultItem] = []
    public var recentSearches: [String] = []
    public var isSearching: Bool = false
    public var isDebouncing: Bool = false
    public var searchErrorMessage: String?
    
    public var hasQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public var hasEmptyResults: Bool {
        hasQuery && searchResults.isEmpty
    }
    
    public var emptyResultsMessage: String {
        "No results found for \"\(searchQuery)\""
    }
    
    public var resultCount: Int {
        searchResults.count
    }
    
    private var modelContext: ModelContext?
    private var indexedMeetings: [Meeting] = []
    private var dataStore: Any?
    private var activeSuggestion: SearchSuggestion?
    private var suggestionLocalUserName = ""
    private var suggestionDate = Date()
    private var suggestionCalendar = Calendar.current
    
    public init(modelContext: ModelContext? = nil, dataStore: Any? = nil) {
        self.modelContext = modelContext
        self.dataStore = dataStore
    }
    
    public func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    public func indexMeetings(_ meetings: [Meeting]) {
        self.indexedMeetings = meetings
    }

    public func activateSuggestion(_ suggestion: SearchSuggestion, localUserName: String = "",
                                   now: Date = Date(), calendar: Calendar = .current) {
        activeSuggestion = suggestion
        suggestionLocalUserName = localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestionDate = now
        suggestionCalendar = calendar
        presentedScope = suggestion == .actionsAssignedToMe ? .actions : .meetings
        selectedScope = suggestion == .actionsAssignedToMe ? .actionItems : .summaries
        search(query: suggestion.title)
    }
    
    public func setPresentedScope(_ scope: SearchPresentedScope) {
        activeSuggestion = nil
        presentedScope = scope
        selectedScope = scope.engineScope
        search(query: searchQuery, recordsHistory: false)
    }

    /// Meetings matched by title, summary or notes, one row per meeting.
    public var meetingHits: [MeetingSearchHit] {
        var order: [UUID] = []
        var titles: [UUID: String] = [:]
        var details: [UUID: String] = [:]
        for result in searchResults {
            switch result.category {
            case .meetingTitle, .summary, .note:
                if titles[result.meetingId] == nil {
                    order.append(result.meetingId)
                    titles[result.meetingId] = result.meetingTitle
                }
                if result.category != .meetingTitle, details[result.meetingId] == nil {
                    details[result.meetingId] = formatSnippet(text: result.snippet, matchTerm: trimmedQuery)
                }
            case .transcript, .actionItem:
                break
            }
        }
        return order.map { MeetingSearchHit(meetingId: $0, title: titles[$0] ?? "", detail: details[$0]) }
    }

    public var transcriptResults: [SearchResultItem] {
        searchResults.filter { $0.category == .transcript }
    }

    public var actionResults: [SearchResultItem] {
        searchResults.filter { $0.category == .actionItem }
    }

    public func setScope(_ scope: SearchScope) {
        activeSuggestion = nil
        self.selectedScope = scope
        switch scope {
        case .transcripts: presentedScope = .transcripts
        case .actionItems: presentedScope = .actions
        case .titles, .summaries, .notes: presentedScope = .meetings
        case .all: presentedScope = .all
        }
        search(query: searchQuery, recordsHistory: false)
    }
    
    public func destination(for result: SearchResultItem) -> NavigationDestination {
        .meetingDetail(id: result.meetingId)
    }
    
    public func performSearch(query: String) {
        search(query: query)
    }
    
    public func search(query: String, recordsHistory: Bool = true) {
        self.searchQuery = query
        searchErrorMessage = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let activeSuggestion, trimmed != activeSuggestion.title {
            self.activeSuggestion = nil
        }
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        if recordsHistory {
            recentSearches.removeAll { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
            recentSearches.insert(trimmed, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
        }
        
        var matches: [SearchResultItem] = []
        let queryLower = trimmed.lowercased()
        
        // Gather meetings to search over
        var candidateMeetings = indexedMeetings
        if candidateMeetings.isEmpty, let context = modelContext {
            let desc = FetchDescriptor<Meeting>()
            do {
                candidateMeetings = try context.fetch(desc)
            } catch {
                searchResults = []
                searchErrorMessage = "Saved meetings could not be searched. Try again; no meeting data was changed."
                isSearching = false
                return
            }
        }

        if let activeSuggestion {
            searchResults = suggestionMatches(activeSuggestion, in: candidateMeetings)
            isSearching = false
            return
        }
        
        for meeting in candidateMeetings {
            // Scope: Meeting Title
            if selectedScope == .all || selectedScope == .titles {
                if meeting.title.lowercased().contains(queryLower) {
                    let range = calculateHighlight(in: meeting.title, term: queryLower)
                    matches.append(SearchResultItem(
                        category: .meetingTitle,
                        meetingId: meeting.id,
                        meetingTitle: meeting.title,
                        snippet: meeting.title,
                        highlightRange: range
                    ))
                }
            }
            
            // Scope: Transcripts
            if selectedScope == .all || selectedScope == .transcripts {
                for seg in meeting.transcriptSegments {
                    if seg.text.lowercased().contains(queryLower) {
                        let range = calculateHighlight(in: seg.text, term: queryLower)
                        matches.append(SearchResultItem(
                            category: .transcript,
                            meetingId: meeting.id,
                            meetingTitle: meeting.title,
                            snippet: seg.text,
                            timecode: seg.startTime,
                            highlightRange: range,
                            speakerName: seg.speakerName
                        ))
                    }
                }
            }
            
            // Scope: Summaries
            if selectedScope == .all || selectedScope == .summaries {
                if let summary = meeting.summary {
                    if summary.executiveSummary.lowercased().contains(queryLower) {
                        let range = calculateHighlight(in: summary.executiveSummary, term: queryLower)
                        matches.append(SearchResultItem(
                            category: .summary,
                            meetingId: meeting.id,
                            meetingTitle: meeting.title,
                            snippet: summary.executiveSummary,
                            highlightRange: range
                        ))
                    }
                    for decision in summary.keyDecisions where decision.lowercased().contains(queryLower) {
                        let range = calculateHighlight(in: decision, term: queryLower)
                        matches.append(SearchResultItem(
                            category: .summary,
                            meetingId: meeting.id,
                            meetingTitle: meeting.title,
                            snippet: decision,
                            highlightRange: range
                        ))
                    }
                }
            }
            
            // Scope: Action Items
            if selectedScope == .all || selectedScope == .actionItems {
                for item in meeting.actionItems {
                    if item.title.lowercased().contains(queryLower) || item.taskDescription.lowercased().contains(queryLower) {
                        let range = calculateHighlight(in: item.title, term: queryLower)
                        matches.append(SearchResultItem(
                            category: .actionItem,
                            meetingId: meeting.id,
                            meetingTitle: meeting.title,
                            snippet: item.title,
                            actionItemId: item.id,
                            highlightRange: range,
                            detail: actionDetail(for: item, meeting: meeting)
                        ))
                    }
                }
            }
            
            // Scope: Notes
            if selectedScope == .all || selectedScope == .notes {
                for note in meeting.notes {
                    if note.content.lowercased().contains(queryLower) {
                        let range = calculateHighlight(in: note.content, term: queryLower)
                        matches.append(SearchResultItem(
                            category: .note,
                            meetingId: meeting.id,
                            meetingTitle: meeting.title,
                            snippet: note.content,
                            timecode: note.timestamp,
                            highlightRange: range
                        ))
                    }
                }
            }
        }
        
        if presentedScope == .meetings && selectedScope == .all {
            matches = matches.filter { $0.category != .transcript && $0.category != .actionItem }
        }
        self.searchResults = matches
        self.isSearching = false
    }
    
    private func suggestionMatches(_ suggestion: SearchSuggestion, in meetings: [Meeting]) -> [SearchResultItem] {
        switch suggestion {
        case .decisionsThisWeek:
            guard let interval = suggestionCalendar.dateInterval(of: .weekOfYear, for: suggestionDate) else { return [] }
            return meetings
                .filter { interval.contains($0.scheduledStartTime ?? $0.createdAt) }
                .flatMap { meeting in
                    (meeting.summary?.keyDecisions ?? []).map { decision in
                        SearchResultItem(category: .summary, meetingId: meeting.id, meetingTitle: meeting.title,
                                         snippet: decision, detail: "Decision")
                    }
                }
        case .actionsAssignedToMe:
            let local = suggestionLocalUserName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !local.isEmpty else { return [] }
            return meetings.flatMap { meeting in
                meeting.actionItems.compactMap { item in
                    let owner = (item.assignee?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    guard owner == local else { return nil }
                    return SearchResultItem(category: .actionItem, meetingId: meeting.id, meetingTitle: meeting.title,
                                            snippet: item.title, actionItemId: item.id,
                                            detail: actionDetail(for: item, meeting: meeting))
                }
            }
        }
    }

    public func formatSnippet(text: String, matchTerm: String, maxLength: Int = 60) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        if let range = trimmed.range(of: matchTerm, options: .caseInsensitive) {
            let matchIndex = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
            let start = max(0, matchIndex - 15)
            let end = min(trimmed.count, start + maxLength)
            let startIndex = trimmed.index(trimmed.startIndex, offsetBy: start)
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: end)
            var snippet = String(trimmed[startIndex..<endIndex])
            if start > 0 { snippet = "..." + snippet }
            if end < trimmed.count { snippet = snippet + "..." }
            return snippet
        } else {
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<endIndex]) + "..."
        }
    }
    
    private func actionDetail(for item: ActionItem, meeting: Meeting) -> String {
        var parts: [String] = [meeting.title]
        if item.assignee != nil { parts.append(item.assigneeName) }
        if let due = item.dueDate {
            parts.append("Due " + due.formatted(.dateTime.day().month(.abbreviated)))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func calculateHighlight(in text: String, term: String) -> Range<Int>? {
        guard let range = text.lowercased().range(of: term) else { return nil }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        return start..<end
    }
    
    public func clearSearch() {
        activeSuggestion = nil
        searchQuery = ""
        searchResults = []
        isSearching = false
    }
    
    public func clearHistory() {
        recentSearches.removeAll()
    }
    
    public func clearRecentSearches() {
        clearHistory()
    }
    
    public func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
    }
}
