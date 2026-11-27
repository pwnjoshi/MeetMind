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
}
