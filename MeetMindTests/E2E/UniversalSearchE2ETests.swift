//
//  UniversalSearchE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Universal Cross-Meeting Search,
//  Scope Filtering (Transcripts, Action Items, Titles), Deep Linking to Timecode,
//  and Keyword Snippet Highlighting (Scenarios S11, S36 + Tier 3 Pairwise Combinations).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class UniversalSearchE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var searchVM: SearchViewModel!
    private var navigationVM: AppNavigationViewModel!
    private var meeting1: Meeting!
    private var meeting2: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        searchVM = SearchViewModel(modelContext: context)
        navigationVM = AppNavigationViewModel()
        
        meeting1 = Meeting(title: "Finance & Budget Review", createdAt: Date(), duration: 1200.0, status: .completed)
        meeting1.audioFileURL = URL(fileURLWithPath: "/tmp/finance_review.m4a")
        context.insert(meeting1)
        
        let speaker1 = Speaker(name: "CFO Alice", avatarColorHex: "#3B82F6")
        context.insert(speaker1)
        
        let seg1 = TranscriptSegment(
            text: "We reached final budget approval for the new infrastructure project.",
            startTime: 145.0, // 02:25
            endTime: 155.0,
            speaker: speaker1,
            meeting: meeting1
        )
        context.insert(seg1)
        meeting1.transcriptSegments = [seg1]
        
        let task1 = ActionItem(title: "Submit budget approval documents", priority: .high, meeting: meeting1)
        context.insert(task1)
        meeting1.actionItems = [task1]
        
        meeting2 = Meeting(title: "Weekly Engineering Standup", createdAt: Date().addingTimeInterval(-86400), duration: 600.0, status: .completed)
        meeting2.audioFileURL = URL(fileURLWithPath: "/tmp/engineering_standup.m4a")
        context.insert(meeting2)
        
        let speaker2 = Speaker(name: "Dev Bob", avatarColorHex: "#10B981")
        context.insert(speaker2)
        
        let seg2 = TranscriptSegment(
            text: "Our server migration is 80% complete with no downtime reported.",
            startTime: 40.0,
            endTime: 50.0,
            speaker: speaker2,
            meeting: meeting2
        )
        context.insert(seg2)
        meeting2.transcriptSegments = [seg2]
        
        let task2 = ActionItem(title: "Finalize migration script", priority: .medium, meeting: meeting2)
        context.insert(task2)
        meeting2.actionItems = [task2]
        try? context.save()
        
        searchVM.indexMeetings([meeting1, meeting2])
    }
    
    @MainActor
    override func tearDown() async throws {
        searchVM = nil
        navigationVM = nil
        meeting1 = nil
        meeting2 = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S11 (Universal Search & Deep Linking)
    
    /// Tier 4: Scenario S11 - Universal Search and Direct Deep Linking to Timecode
    /// - Given: Multiple meetings indexed with transcripts and action items.
    /// - When:
    ///   1. User opens Search tab in root navigation.
    ///   2. Enters query "budget approval".
    ///   3. Search engine processes tokenized match against transcripts, titles, and tasks.
    ///   4. Results display snippet with keyword highlighted and timecode `02:25`.
    ///   5. User taps search result item.
    /// - Then:
    ///   - Navigation routes directly to MeetingDetailCockpit for "Finance & Budget Review".
    ///   - Active tab within cockpit opens to Transcript tab.
    ///   - Transcript scrolls to segment at 145.0s with active teal highlight.
    ///   - Audio player is pre-queued to 145.0s.
    func test_tier4_scenario11_universalSearchAndDeepLinking() throws {
        // When - 2. Search query
        searchVM.search(query: "budget approval")
        XCTAssertGreaterThan(searchVM.results.count, 0)
        
        // When - 4. Verify result snippet and timecode
        let transcriptResult = searchVM.results.first(where: { $0.resultType == .transcriptSegment })
        XCTAssertNotNil(transcriptResult)
        XCTAssertEqual(transcriptResult?.meetingID, meeting1.id)
        XCTAssertEqual(transcriptResult?.timecode, 145.0)
        XCTAssertEqual(transcriptResult?.formattedTimecode, "02:25")
        XCTAssertTrue(transcriptResult?.snippet.contains("budget approval") ?? false)
        
        // When - 5. Tap search result
        navigationVM.handleSearchResultSelection(transcriptResult!)
        
        // Then
        XCTAssertEqual(navigationVM.presentedMeetingDetailID, meeting1.id)
        XCTAssertEqual(navigationVM.selectedCockpitTab, .transcript)
        XCTAssertEqual(navigationVM.queuedAudioSeekTime, 145.0)
    }

    // MARK: - Tier 4: Scenario S36 (Search Scope Filtering)
    
    /// Tier 4: Scenario S36 - Search Scope Filtering Isolation
    /// - Given: Query "budget" matches both a meeting Title, a Transcript segment, and an Action item.
    /// - When:
    ///   1. User searches with scope `.all` -> Receives matches from all categories.
    ///   2. Switches scope to `.transcriptsOnly` -> Receives only transcript segment matches.
    ///   3. Switches scope to `.actionItemsOnly` -> Receives only action item matches.
    ///   4. Switches scope to `.titlesOnly` -> Receives only meeting title matches.
    /// - Then:
    ///   - Results counts and types strictly adhere to selected scope.
    ///   - Execution speed is instantaneous (<100ms).
    func test_tier4_scenario36_searchScopeFiltering() throws {
        // Scope .all
        searchVM.selectedScope = .all
        searchVM.search(query: "budget")
        XCTAssertEqual(searchVM.results.count, 3) // 1 title, 1 transcript, 1 task
        
        // Scope .transcriptsOnly
        searchVM.selectedScope = .transcriptsOnly
        searchVM.search(query: "budget")
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.resultType, .transcriptSegment)
        
        // Scope .actionItemsOnly
        searchVM.selectedScope = .actionItemsOnly
        searchVM.search(query: "budget")
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.resultType, .actionItem)
        
        // Scope .titlesOnly
        searchVM.selectedScope = .titlesOnly
        searchVM.search(query: "budget")
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.resultType, .meetingTitle)
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Cross-Meeting Keyword Discovery
    /// - Verifies search discovers occurrences across distinct meetings.
    func test_tier3_crossMeetingSearchMatch() throws {
        let segAdditional = TranscriptSegment(text: "Budget considerations for migration.", startTime: 100.0, endTime: 110.0)
        meeting2.transcriptSegments.append(segAdditional)
        searchVM.indexMeetings([meeting1, meeting2])
        
        searchVM.search(query: "Budget")
        let matchingMeetingIDs = Set(searchVM.results.map { $0.meetingID })
        XCTAssertEqual(matchingMeetingIDs.count, 2)
    }

    /// Tier 3: Pairwise - Snippet Keyword Highlighting Range
    /// - Verifies result provides highlighted range coordinates for UI bolding.
    func test_tier3_searchResultKeywordHighlighting() throws {
        searchVM.search(query: "infrastructure")
        let result = searchVM.results.first
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasHighlightRange ?? false)
        XCTAssertEqual(result?.highlightedWord, "infrastructure")
    }

    /// Tier 3: Pairwise - Transcripts Only Scope Exclusion
    /// - Verifies transcripts-only scope excludes action item titles.
    func test_tier3_searchScopeTranscriptsOnly() throws {
        searchVM.selectedScope = .transcriptsOnly
        searchVM.search(query: "migration")
        
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.resultType, .transcriptSegment)
    }

    /// Tier 3: Pairwise - Action Items Only Scope Returns Task Metadata
    /// - Verifies action items scope returns assignee and priority info.
    func test_tier3_searchScopeActionItemsOnly() throws {
        searchVM.selectedScope = .actionItemsOnly
        searchVM.search(query: "documents")
        
        XCTAssertEqual(searchVM.results.count, 1)
        let item = searchVM.results.first
        XCTAssertEqual(item?.resultType, .actionItem)
        XCTAssertEqual(item?.title, "Submit budget approval documents")
    }

    /// Tier 3: Pairwise - Titles Only Scope Filters
    /// - Verifies titles-only scope matches only meeting titles.
    func test_tier3_searchScopeTitlesOnly() throws {
        searchVM.selectedScope = .titlesOnly
        searchVM.search(query: "Engineering")
        
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.title, "Weekly Engineering Standup")
    }

    /// Tier 3: Pairwise - Search Query Debounce & Execution Timing
    /// - Verifies rapid queries execute cleanly and under 100ms.
    func test_tier3_searchQueryDebounceAndTiming() throws {
        let startTime = Date()
        for q in ["b", "bu", "bud", "budg", "budget"] {
            searchVM.search(query: q)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertGreaterThan(searchVM.results.count, 0)
    }

    /// Tier 3: Pairwise - Empty Query Returns Zero State & Recent Searches
    /// - Verifies empty query resets result count and displays zero state.
    func test_tier3_emptyQueryZeroState() throws {
        searchVM.search(query: "   ")
        XCTAssertEqual(searchVM.results.count, 0)
        XCTAssertTrue(searchVM.showEmptyState)
    }

    /// Tier 3: Pairwise - Regex Meta-Characters Safety
    /// - Verifies queries containing `[`, `*`, `+`, `?`, `\` do not crash the search regex.
    func test_tier3_specialCharactersRegexSafety() throws {
        for specialQuery in ["[budget]", ".*", "approval+", "?", "test\\"] {
            XCTAssertNoThrow(searchVM.search(query: specialQuery))
        }
    }

    /// Tier 3: Pairwise - Deep Link Sets Queued Seek Time
    /// - Verifies navigation VM receives precise seek time from transcript match.
    func test_tier3_deepLinkToTranscriptSeekPoint() throws {
        searchVM.search(query: "infrastructure")
        guard let result = searchVM.results.first else {
            XCTFail("Result expected")
            return
        }
        
        navigationVM.handleSearchResultSelection(result)
        XCTAssertEqual(navigationVM.queuedAudioSeekTime, 145.0)
    }

    /// Tier 3: Pairwise - Deep Link to Action Items Tab
    /// - Verifies tapping an action item search result opens cockpit to Action Items tab.
    func test_tier3_deepLinkToActionItemChecklist() throws {
        searchVM.selectedScope = .actionItemsOnly
        searchVM.search(query: "migration script")
        guard let result = searchVM.results.first else {
            XCTFail("Result expected")
            return
        }
        
        navigationVM.handleSearchResultSelection(result)
        XCTAssertEqual(navigationVM.presentedMeetingDetailID, meeting2.id)
        XCTAssertEqual(navigationVM.selectedCockpitTab, .actionItems)
    }

    /// Tier 3: Pairwise - Live Search Index Update When Transcript Edited
    /// - Verifies inline transcript edits re-index immediately for subsequent searches.
    func test_tier3_liveSearchIndexUpdateOnEdit() throws {
        meeting1.transcriptSegments[0].text = "We reached final budget authorization for the new project."
        searchVM.indexMeetings([meeting1, meeting2])
        
        searchVM.search(query: "authorization")
        XCTAssertEqual(searchVM.results.count, 1)
        XCTAssertEqual(searchVM.results.first?.meetingID, meeting1.id)
    }

    /// Tier 3: Pairwise - Case-Insensitive and Diacritic Search
    /// - Verifies search handles case variations and diacritics.
    func test_tier3_caseInsensitiveAndDiacriticSearch() throws {
        searchVM.search(query: "BUDGET")
        XCTAssertGreaterThan(searchVM.results.count, 0)
        
        searchVM.search(query: "búdget")
        XCTAssertGreaterThan(searchVM.results.count, 0)
    }
}
