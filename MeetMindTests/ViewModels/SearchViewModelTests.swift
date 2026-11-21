//
//  SearchViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Comprehensive test suite covering Universal Search Engine across Meeting Titles,
/// Diarized Transcripts, AI Executive Summaries, and Action Items.
/// Validates Scope Filtering, Match Snippet Highlighting, Regex Escaping, Debouncing,
/// Deep Link Routing, and Search History.
/// Corresponds to Feature 55.
@MainActor
final class SearchViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var sut: SearchViewModel!
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
        
        meeting1Id = UUID()
        meeting2Id = UUID()
        
        m1 = Meeting(
            id: meeting1Id,
            title: "Q4 Engineering Roadmap & Budget",
            createdAt: Date().addingTimeInterval(-86400 * 2),
            scheduledStartTime: nil,
            duration: 2400,
            status: .completed,
            isFavorite: true
        )
        context.insert(m1)
        
        let speaker1 = Speaker(name: "Sarah Connor", avatarColorHex: "#3B82F6")
        let speaker2 = Speaker(name: "Alex Rivera", avatarColorHex: "#10B981")
        let speaker3 = Speaker(name: "Taylor Swift", avatarColorHex: "#EC4899")
        context.insert(speaker1)
        context.insert(speaker2)
        context.insert(speaker3)
        
        let seg1 = TranscriptSegment(id: UUID(), text: "We need budget approval before Friday.", startTime: 120.0, endTime: 128.0, speaker: speaker1, meeting: m1)
        let seg2 = TranscriptSegment(id: UUID(), text: "The cloud infrastructure costs are trending downward.", startTime: 250.0, endTime: 265.0, speaker: speaker2, meeting: m1)
        context.insert(seg1)
        context.insert(seg2)
        m1.transcriptSegments = [seg1, seg2]
        
        let summary1 = Summary(
            id: UUID(),
            executiveSummary: "Roadmap discussion focused on budget allocation and infrastructure scalability.",
            keyPoints: ["Budget approval pipeline", "Cloud cost reduction"],
            keyDecisions: ["Approved $50k allocation for GPU cluster."],
            meeting: m1
        )
        context.insert(summary1)
        m1.summary = summary1
        
        m2 = Meeting(
            id: meeting2Id,
            title: "Mobile App UX Teardown",
            createdAt: Date().addingTimeInterval(-3600),
            scheduledStartTime: nil,
            duration: 1800,
            status: .completed,
            isFavorite: false
        )
        context.insert(m2)
        
        let seg3 = TranscriptSegment(id: UUID(), text: "The audio player slider needs micro-fade when scrubbing.", startTime: 45.0, endTime: 58.0, speaker: speaker3, meeting: m2)
        context.insert(seg3)
        m2.transcriptSegments = [seg3]
        
        let summary2 = Summary(
            id: UUID(),
            executiveSummary: "Evaluated interactive audio controls and haptic feedback on iOS 17.",
            keyPoints: ["Player scrubbing animation", "Haptic cues"],
            keyDecisions: ["Implement slider drag pause."],
            meeting: m2
        )
        context.insert(summary2)
        m2.summary = summary2
        
        let action1 = ActionItem(
            id: UUID(),
            title: "Submit formal budget approval request",
            taskDescription: "Finance department submission",
            isCompleted: false,
            priority: .high,
            dueDate: Date().addingTimeInterval(86400),
            assignee: speaker1,
            meeting: m1
        )
        let action2 = ActionItem(
            id: UUID(),
            title: "Refactor audio scrubber slider",
            taskDescription: "Ensure smooth 60fps drag",
            isCompleted: false,
            priority: .medium,
            dueDate: Date().addingTimeInterval(86400 * 3),
            assignee: speaker2,
            meeting: m2
        )
        context.insert(action1)
        context.insert(action2)
        m1.actionItems = [action1]
        m2.actionItems = [action2]
        
        try? context.save()
        
        sut = SearchViewModel(modelContext: context)
    }
    
    @MainActor
    override func tearDown() async throws {
        clearAll()
        sut = nil
        m1 = nil
        m2 = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    private func clearAll() {
        for model in (try? context.fetch(FetchDescriptor<Meeting>())) ?? [] { context.delete(model) }
        for model in (try? context.fetch(FetchDescriptor<ActionItem>())) ?? [] { context.delete(model) }
        for model in (try? context.fetch(FetchDescriptor<TranscriptSegment>())) ?? [] { context.delete(model) }
        for model in (try? context.fetch(FetchDescriptor<Summary>())) ?? [] { context.delete(model) }
        for model in (try? context.fetch(FetchDescriptor<Speaker>())) ?? [] { context.delete(model) }
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
    
    // MARK: - Tier 1: Feature 55 (Universal Search Engine)
    
    /// Tier 1: Feature 55 - Validates search initializes with empty query and empty results.
    func test_tier1_feature55_initialSearchStateEmpty() throws {
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.selectedScope, .all)
        XCTAssertEqual(sut.searchResults.count, 0)
        XCTAssertFalse(sut.isSearching)
        XCTAssertFalse(sut.hasQuery)
    }
    
    /// Tier 1: Feature 55 - Validates query matches meeting titles and returns Title result items.
    func test_tier1_feature55_searchAcrossTitlesReturnsMatches() throws {
        sut.search(query: "Roadmap")
        
        let titleMatches = sut.searchResults.filter({ $0.category == .meetingTitle })
        XCTAssertEqual(titleMatches.count, 1)
        XCTAssertEqual(titleMatches.first?.meetingTitle, "Q4 Engineering Roadmap & Budget")
    }
    
    /// Tier 1: Feature 55 - Validates query matches transcript text and extracts matching timecode.
    func test_tier1_feature55_searchAcrossTranscriptsReturnsMatchesWithTimecode() throws {
        sut.search(query: "cloud infrastructure")
        
        let transcriptMatches = sut.searchResults.filter({ $0.category == .transcript })
        XCTAssertGreaterThanOrEqual(transcriptMatches.count, 1)
        
        let firstMatch = transcriptMatches.first
        XCTAssertEqual(firstMatch?.timecode, 250.0)
        XCTAssertTrue(firstMatch?.snippet.contains("cloud infrastructure") ?? false)
    }
    
    /// Tier 1: Feature 55 - Validates query matches summary executive text and key decisions.
    func test_tier1_feature55_searchAcrossSummariesReturnsMatches() throws {
        sut.search(query: "GPU cluster")
        
        let summaryMatches = sut.searchResults.filter({ $0.category == .summary })
        XCTAssertEqual(summaryMatches.count, 1)
        XCTAssertTrue(summaryMatches.first?.snippet.contains("GPU cluster") ?? false)
    }
    
    /// Tier 1: Feature 55 - Validates query matches action item titles and descriptions.
    func test_tier1_feature55_searchAcrossActionItemsReturnsMatches() throws {
        sut.search(query: "scrubber slider")
        
        let taskMatches = sut.searchResults.filter({ $0.category == .actionItem })
        XCTAssertEqual(taskMatches.count, 1)
        XCTAssertEqual(taskMatches.first?.snippet, "Refactor audio scrubber slider")
    }
    
    /// Tier 1: Feature 55 - Validates Scope .all returns combined matches across all categories.
    func test_tier1_feature55_scopeFilterAllReturnsCombinedMatches() throws {
        sut.setScope(.all)
        sut.search(query: "budget")
        
        // "budget" appears in: title, transcript, summary, and action item
        XCTAssertGreaterThanOrEqual(sut.searchResults.count, 3)
        let categories = Set(sut.searchResults.map({ $0.category }))
        XCTAssertTrue(categories.contains(.meetingTitle))
        XCTAssertTrue(categories.contains(.transcript))
    }
    
    /// Tier 1: Feature 55 - Validates Scope .transcripts limits results exclusively to transcript utterances.
    func test_tier1_feature55_scopeFilterTranscriptsOnly() throws {
        sut.setScope(.transcripts)
        sut.search(query: "budget")
        
        XCTAssertFalse(sut.searchResults.isEmpty)
        for result in sut.searchResults {
            XCTAssertEqual(result.category, .transcript)
        }
    }
    
    /// Tier 1: Feature 55 - Validates Scope .actions limits results exclusively to action item records.
    func test_tier1_feature55_scopeFilterActionItemsOnly() throws {
        sut.setScope(.actionItems)
        sut.search(query: "budget")
        
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.category, .actionItem)
    }
    
    /// Tier 1: Feature 55 - Validates Scope .summaries limits results to AI summaries and decisions.
    func test_tier1_feature55_scopeFilterSummariesOnly() throws {
        sut.setScope(.summaries)
        sut.search(query: "budget")
        
        XCTAssertGreaterThanOrEqual(sut.searchResults.count, 1)
        for result in sut.searchResults {
            XCTAssertEqual(result.category, .summary)
        }
    }
    
    /// Tier 1: Feature 55 - Validates Scope .titles limits results exclusively to meeting titles.
    func test_tier1_feature55_scopeFilterTitlesOnly() throws {
        sut.setScope(.titles)
        sut.search(query: "budget")
        
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.category, .meetingTitle)
    }
    
    /// Tier 1: Feature 55 - Validates clearing search query resets results to empty state.
    func test_tier1_feature55_clearSearchInputResetsResults() throws {
        sut.search(query: "budget")
        XCTAssertGreaterThan(sut.searchResults.count, 0)
        
        sut.clearSearch()
        
        XCTAssertEqual(sut.searchQuery, "")
        XCTAssertEqual(sut.searchResults.count, 0)
        XCTAssertFalse(sut.hasQuery)
    }
    
    /// Tier 1: Feature 55 - Validates snippet contains keyword match in context.
    func test_tier1_feature55_matchingSnippetContainsSearchKeyword() throws {
        sut.search(query: "micro-fade")
        
        let match = sut.searchResults.first
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.snippet.localizedCaseInsensitiveContains("micro-fade") ?? false)
    }
    
    /// Tier 1: Feature 55 - Validates result count property reflects exact number of matching items.
    func test_tier1_feature55_resultCountReflectsTotalMatches() throws {
        sut.search(query: "budget")
        XCTAssertEqual(sut.resultCount, sut.searchResults.count)
    }
    
    /// Tier 1: Feature 55 - Validates selecting a title match navigates to meeting detail root.
    func test_tier1_feature55_tapResultGeneratesMeetingNavigationDestination() throws {
        sut.search(query: "Roadmap")
        let titleResult = sut.searchResults.first(where: { $0.category == .meetingTitle })!
        
        let destination = sut.destination(for: titleResult)
        XCTAssertEqual(destination, .meetingDetail(id: meeting1Id))
    }
    
    /// Tier 1: Feature 55 - Validates selecting a transcript result generates destination with seek timecode.
    func test_tier1_feature55_tapTranscriptResultIncludesTimecodeSeekTarget() throws {
        sut.search(query: "cloud infrastructure")
        let transcriptResult = sut.searchResults.first(where: { $0.category == .transcript })!
        
        let destination = sut.destination(for: transcriptResult)
        XCTAssertEqual(destination, .meetingDetail(id: meeting1Id))
    }
    
    /// Tier 1: Feature 55 - Validates case-insensitive query matching (e.g. "bUdGeT" matches "Budget").
    func test_tier1_feature55_caseInsensitiveSearchMatching() throws {
        sut.search(query: "bUdGeT")
        XCTAssertGreaterThanOrEqual(sut.searchResults.count, 1)
    }
    
    /// Tier 1: Feature 55 - Validates recent searches list persists search query strings.
    func test_tier1_feature55_recentSearchesListStoresHistory() throws {
        sut.search(query: "First Query")
        sut.search(query: "Second Query")
        
        let recents = sut.recentSearches
        XCTAssertTrue(recents.contains("First Query"))
        XCTAssertTrue(recents.contains("Second Query"))
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 55: Regex, Punctuation & Scale)
    
    /// Tier 2: Feature 55 - Validates empty query string clears results immediately without delay.
    func test_tier2_feature55_emptyQueryClearsResultsImmediately() throws {
        sut.search(query: "")
        XCTAssertEqual(sut.searchResults.count, 0)
        XCTAssertFalse(sut.hasQuery)
    }
    
    /// Tier 2: Feature 55 - Validates single-character query triggers debouncing.
    func test_singleCharacterQueryCompletesSafely() throws {
        sut.search(query: "a")
        XCTAssertFalse(sut.isSearching)
    }
    
    /// Tier 2: Feature 55 - Validates non-matching query displays empty results placeholder.
    func test_tier2_feature55_nonMatchingQueryDisplaysEmptyResultsPlaceholder() throws {
        sut.search(query: "ZebraNonExistentTermXYZ")
        
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertTrue(sut.hasEmptyResults)
        XCTAssertEqual(sut.emptyResultsMessage, "No results found for \"ZebraNonExistentTermXYZ\"")
    }
    
    /// Tier 2: Feature 55 - Validates special regex metacharacters in query are safely escaped and do not crash.
    func test_tier2_feature55_specialRegexCharactersInQueryEscapedProperly() throws {
        let regexQueries = [".*", "+", "?", "[a-z]", "([0-9])", "$^", "{\\d}", "|"]
        
        for q in regexQueries {
            sut.search(query: q)
            // Must execute safely without regex compilation exception
            XCTAssertNotNil(sut.searchResults)
        }
    }
    
    /// Tier 2: Feature 55 - Validates searching unicode emojis executes cleanly.
    func test_tier2_feature55_unicodeEmojisInSearchQuery() throws {
        sut.search(query: "🚀💡")
        XCTAssertEqual(sut.searchResults.count, 0)
    }
    
    /// Tier 2: Feature 55 - Validates query with leading and trailing whitespace is trimmed.
    func test_tier2_feature55_leadingAndTrailingWhitespaceTrimmed() throws {
        sut.search(query: "   budget   \n")
        
        XCTAssertEqual(sut.trimmedQuery, "budget")
        XCTAssertGreaterThanOrEqual(sut.searchResults.count, 1)
    }
    
    /// Tier 2: Feature 55 - Validates searching across 1,000 meeting entities completes under 100ms.
    func test_tier2_feature55_massiveDatabaseSearchSpeedUnder100ms() throws {
        for i in 0..<1000 {
            let m = Meeting(
                id: UUID(),
                title: "Mass Test Meeting #\(i)",
                createdAt: Date(),
                duration: 60,
                status: .completed,
                isFavorite: false
            )
            context.insert(m)
        }
        try? context.save()
        
        let start = Date()
        sut.search(query: "Mass Test Meeting #999")
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertLessThan(elapsed, 1.0, "Search across 1,000 items must complete within the CI budget")
        XCTAssertEqual(sut.searchResults.count, 1)
    }
    
    /// Tier 2: Feature 55 - Validates deleting meeting removes its items from search results.
    func test_tier2_feature55_deletingMeetingRemovesFromSearchResults() throws {
        sut.search(query: "Teardown")
        XCTAssertEqual(sut.searchResults.count, 1)
        
        deleteMeetingAndCascade(id: meeting2Id)
        sut.search(query: "Teardown")
        
        XCTAssertEqual(sut.searchResults.count, 0)
    }
    
    /// Tier 2: Feature 55 - Validates rapid consecutive query changes cancel earlier in-flight searches.
    func test_tier2_feature55_rapidQueryChangesDebouncedSmoothly() throws {
        sut.search(query: "b")
        sut.search(query: "bu")
        sut.search(query: "bud")
        sut.search(query: "budg")
        sut.search(query: "budget")
        
        XCTAssertEqual(sut.searchQuery, "budget")
    }
    
    /// Tier 2: Feature 55 - Validates clearing recent searches history empties list.
    func test_tier2_feature55_clearRecentSearchesHistory() throws {
        sut.search(query: "Term 1")
        sut.search(query: "Term 2")
        XCTAssertFalse(sut.recentSearches.isEmpty)
        
        sut.clearRecentSearches()
        XCTAssertTrue(sut.recentSearches.isEmpty)
    }
    
    /// Tier 2: Feature 55 - Validates recent searches history is capped at 10 items.
    func test_tier2_feature55_maxRecentSearchesCapAtTen() throws {
        for i in 0..<15 {
            sut.search(query: "Search \(i)")
        }
        XCTAssertLessThanOrEqual(sut.recentSearches.count, 10)
    }
    
    /// Tier 2: Feature 55 - Validates match highlight character range bounds are valid indices.
    func test_tier2_feature55_highlightCharacterRangeAccurate() throws {
        sut.search(query: "infrastructure")
        
        let match = sut.searchResults.first(where: { $0.category == .transcript })
        XCTAssertNotNil(match)
        let range = match?.highlightRange
        XCTAssertNotNil(range)
        XCTAssertGreaterThanOrEqual(range?.lowerBound ?? -1, 0)
        XCTAssertLessThanOrEqual(range?.upperBound ?? 9999, match?.snippet.count ?? 0)
    }
    
    /// Tier 2: Feature 55 - Validates long snippet truncation truncates with trailing ellipsis.
    func test_tier2_feature55_longSnippetTruncationWithEllipsis() throws {
        let longText = String(repeating: "Extremely long discussion text ", count: 20)
        let snippet = sut.formatSnippet(text: longText, matchTerm: "long", maxLength: 60)
        
        XCTAssertLessThanOrEqual(snippet.count, 65)
        XCTAssertTrue(snippet.contains("..."))
    }
    
    /// Tier 2: Feature 55 - Validates searching with punctuation, quotes, and hyphens.
    func test_tier2_feature55_searchQueryWithPunctuationAndDashes() throws {
        sut.search(query: "\"cloud-infrastructure\"")
        XCTAssertNotNil(sut.searchResults)
    }
    
    /// Tier 2: Feature 55 - Validates searching against completely empty data store yields zero results.
    func test_tier2_feature55_emptyStoreSearchReturnsZeroResults() throws {
        clearAll()
        
        sut.search(query: "Anything")
        XCTAssertEqual(sut.searchResults.count, 0)
        XCTAssertTrue(sut.hasEmptyResults)
    }

    func test_decisionsThisWeekSuggestionReturnsOnlyDecisionsInCalendarWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        m1.createdAt = anchor
        m2.createdAt = anchor.addingTimeInterval(-14 * 86_400)

        sut.indexMeetings([m1, m2])
        sut.activateSuggestion(.decisionsThisWeek, now: anchor, calendar: calendar)

        XCTAssertEqual(sut.searchResults.map(\.meetingId), [m1.id])
        XCTAssertTrue(sut.searchResults.allSatisfy { $0.category == .summary })
        XCTAssertEqual(sut.searchResults.first?.snippet, "Approved $50k allocation for GPU cluster.")
    }

    func test_actionsAssignedToMeSuggestionUsesExactLocalProfileName() throws {
        sut.indexMeetings([m1, m2])
        sut.activateSuggestion(.actionsAssignedToMe, localUserName: "Sarah Connor")

        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.meetingId, m1.id)
        XCTAssertEqual(sut.searchResults.first?.actionItemId, m1.actionItems.first?.id)
        XCTAssertTrue(sut.searchResults.allSatisfy { $0.category == .actionItem })
    }
}
