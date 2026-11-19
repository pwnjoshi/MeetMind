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
    
    public init(
        id: UUID = UUID(),
        category: SearchResultCategory,
        meetingId: UUID,
        meetingTitle: String,
        snippet: String,
        timecode: TimeInterval? = nil,
        actionItemId: UUID? = nil,
        highlightRange: Range<Int>? = nil
    ) {
        self.id = id
        self.category = category
        self.meetingId = meetingId
        self.meetingTitle = meetingTitle
        self.snippet = snippet
        self.timecode = timecode
        self.actionItemId = actionItemId
        self.highlightRange = highlightRange
    }
}

/// ViewModel coordinating cross-entity universal search, debouncing, highlighting, and search history
@Observable
@MainActor
public final class SearchViewModel {
    public var searchQuery: String = ""
    public var selectedScope: SearchScope = .all
    public var searchResults: [SearchResultItem] = []
    public var recentSearches: [String] = []
    public var isSearching: Bool = false
    public var isDebouncing: Bool = false
    
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
    
    public func setScope(_ scope: SearchScope) {
        self.selectedScope = scope
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let fetched = try? context.fetch(desc) {
                candidateMeetings = fetched
            }
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
                            highlightRange: range
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
                            highlightRange: range
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
        
        self.searchResults = matches
        self.isSearching = false
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
    
    private func calculateHighlight(in text: String, term: String) -> Range<Int>? {
        guard let range = text.lowercased().range(of: term) else { return nil }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        return start..<end
    }
    
    public func clearSearch() {
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
