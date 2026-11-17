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
    
    func test_actionItemFilterHeaderView_selection() throws {
        var selectedScope: ActionItemFilterScope = .all
        var selectedGrouping: ActionItemGrouping = .none
        
        let header = ActionItemFilterHeaderView(
            selectedScope: .all,
            selectedGrouping: .none,
            onSelectScope: { selectedScope = $0 },
            onSelectGrouping: { selectedGrouping = $0 }
        )
        XCTAssertNotNil(header)
        header.onSelectScope(.urgent)
        XCTAssertEqual(selectedScope, .urgent)
        header.onSelectGrouping(.priority)
        XCTAssertEqual(selectedGrouping, .priority)
    }
    
    func test_actionItemRowView_toggle() throws {
        let item = ActionItem(title: "Write documentation", priority: .medium)
        var didToggle = false
        var didSelectMeeting = false
        
        let row = ActionItemRowView(
            item: item,
            onToggle: { didToggle = true },
            onSelectMeeting: { didSelectMeeting = true }
        )
        XCTAssertNotNil(row)
        XCTAssertEqual(row.item.title, "Write documentation")
        
        row.onToggle()
        XCTAssertTrue(didToggle)
        row.onSelectMeeting?()
        XCTAssertTrue(didSelectMeeting)
    }
    
    func test_createActionItemSheet_saving() throws {
        var savedTitle: String? = nil
        var savedPriority: ActionPriority? = nil
        var didDismiss = false
        
        let sheet = CreateActionItemSheet(
            onSave: { title, priority, _, _ in
                savedTitle = title
                savedPriority = priority
            },
            onDismiss: { didDismiss = true }
        )
        XCTAssertNotNil(sheet)
        sheet.onSave("Implement OAuth", .high, nil, "Sarah")
        XCTAssertEqual(savedTitle, "Implement OAuth")
        XCTAssertEqual(savedPriority, .high)
        sheet.onDismiss()
        XCTAssertTrue(didDismiss)
    }
}
