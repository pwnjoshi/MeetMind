import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class SearchConsoleViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var searchVM: SearchViewModel!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        
        let meeting = Meeting(title: "Architecture Strategy", status: .completed)
        let seg = TranscriptSegment(text: "We should focus on offline-first sync.", startTime: 10, endTime: 15, meeting: meeting)
        meeting.addTranscriptSegment(seg)
        context.insert(meeting)
        
        searchVM = SearchViewModel(modelContext: context)
        searchVM.indexMeetings([meeting])
    }
    
    override func tearDownWithError() throws {
        searchVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_searchConsoleView_initialization() throws {
        let view = SearchConsoleView(viewModel: searchVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.viewModel.selectedScope, .all)
        XCTAssertFalse(view.viewModel.hasQuery)
    }
    
    func test_searchScopeFilterBar_selection() throws {
        var selectedScope: SearchScope = .all
        let bar = SearchScopeFilterBar(selectedScope: .all) { scope in
            selectedScope = scope
        }
        XCTAssertNotNil(bar)
        bar.onSelectScope(.transcripts)
        XCTAssertEqual(selectedScope, .transcripts)
    }
    
    func test_recentSearchesView_interaction() throws {
        var selectedQuery: String? = nil
        var didClear = false
        let recents = RecentSearchesView(
            recentSearches: ["Budget", "Strategy"],
            onSelect: { selectedQuery = $0 },
            onClear: { didClear = true }
        )
        XCTAssertNotNil(recents)
        XCTAssertEqual(recents.recentSearches.count, 2)
        recents.onSelect("Budget")
        XCTAssertEqual(selectedQuery, "Budget")
        recents.onClear()
        XCTAssertTrue(didClear)
    }
    
    func test_searchResultRowView_rendering() throws {
        let item = SearchResultItem(
            category: .transcript,
            meetingId: UUID(),
            meetingTitle: "Architecture Strategy",
            snippet: "focus on offline-first sync",
            timecode: 10.0
        )
        var didSelect = false
        let row = SearchResultRowView(result: item) {
            didSelect = true
        }
        XCTAssertNotNil(row)
        XCTAssertEqual(row.result.meetingTitle, "Architecture Strategy")
        XCTAssertEqual(row.result.category, .transcript)
        XCTAssertEqual(row.result.timecode, 10.0)
        row.onSelect()
        XCTAssertTrue(didSelect)
    }
}
