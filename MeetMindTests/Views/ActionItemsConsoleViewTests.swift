import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class ActionItemsConsoleViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var actionVM: ActionItemsViewModel!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        
        let meeting = Meeting(title: "Product Roadmap", status: .completed)
        let item1 = ActionItem(title: "Update design tokens", priority: .high, meeting: meeting)
        let item2 = ActionItem(title: "Verify API payload", isCompleted: true, priority: .urgent, meeting: meeting)
        context.insert(meeting)
        context.insert(item1)
        context.insert(item2)
        
        actionVM = ActionItemsViewModel()
        actionVM.allActionItems = [item1, item2]
    }
    
    override func tearDownWithError() throws {
        actionVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_actionItemsConsoleView_initialization() throws {
        let view = ActionItemsConsoleView(viewModel: actionVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.viewModel.allActionItems.count, 2)
        XCTAssertEqual(view.viewModel.selectedFilterScope, .all)
    }
}
