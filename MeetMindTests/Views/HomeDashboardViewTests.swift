import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class HomeDashboardViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var homeVM: HomeViewModel!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        homeVM = HomeViewModel(modelContext: context)
    }
    
    override func tearDownWithError() throws {
        homeVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_homeDashboardView_initialization() throws {
        let view = HomeDashboardView(viewModel: homeVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.viewModel.selectedFilter, .all)
        XCTAssertEqual(view.viewModel.searchText, "")
    }
    
    func test_upcomingMeetingCard_initializationAndCallbacks() throws {
        let meeting = Meeting(title: "Design Review", scheduledStartTime: Date().addingTimeInterval(3600), status: .scheduled)
        var didStart = false
        var didSelect = false
        
        let card = UpcomingMeetingCard(
            meeting: meeting,
            countdownText: "Starts in 60 mins",
            onStartNow: { didStart = true },
            onSelect: { didSelect = true }
        )
        
        XCTAssertNotNil(card)
        XCTAssertEqual(card.meeting.title, "Design Review")
        XCTAssertEqual(card.countdownText, "Starts in 60 mins")
        
        card.onStartNow?()
        XCTAssertTrue(didStart)
        
        card.onSelect?()
        XCTAssertTrue(didSelect)
    }
    
    func test_recentMeetingCard_initializationAndStarToggle() throws {
        let meeting = Meeting(title: "Architecture Sync", duration: 1800, status: .completed, isFavorite: false)
        var didStar = false
        var didSelect = false
        
        let card = RecentMeetingCard(
            meeting: meeting,
            onSelect: { didSelect = true },
            onToggleStar: { didStar = true }
        )
        
        XCTAssertNotNil(card)
        XCTAssertEqual(card.meeting.title, "Architecture Sync")
        
        card.onToggleStar?()
        XCTAssertTrue(didStar)
        
        card.onSelect?()
        XCTAssertTrue(didSelect)
    }
    
    func test_filterChipBar_selectionState() throws {
        var selectedFilter = MeetingFilter.all
        var callbackFilter: MeetingFilter? = nil
        
        let binding = Binding<MeetingFilter>(
            get: { selectedFilter },
            set: { selectedFilter = $0 }
        )
        
        let bar = FilterChipBar(selectedFilter: binding) { filter in
            callbackFilter = filter
        }
        
        XCTAssertNotNil(bar)
        bar.onSelectFilter?(.today)
        XCTAssertEqual(callbackFilter, .today)
    }
    
    func test_recordFABButton_actionExecution() throws {
        var actionExecuted = false
        let fab = RecordFABButton {
            actionExecuted = true
        }
        
        XCTAssertNotNil(fab)
        fab.action()
        XCTAssertTrue(actionExecuted)
    }
}
