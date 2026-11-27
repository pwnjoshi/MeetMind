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
}
