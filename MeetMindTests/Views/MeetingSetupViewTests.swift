import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingSetupViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var setupVM: MeetingSetupViewModel!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        setupVM = MeetingSetupViewModel(modelContext: context)
    }
    
    override func tearDownWithError() throws {
        setupVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_newMeetingOptionCard_execution() throws {
        var tapped = false
        let card = NewMeetingOptionCard(
            title: "Quick Start",
            subtitle: "Start recording immediately",
            iconName: "record.circle",
            tintColor: .red,
            backgroundColor: .pink,
            action: { tapped = true }
        )
        
        XCTAssertNotNil(card)
        XCTAssertEqual(card.title, "Quick Start")
        card.action()
        XCTAssertTrue(tapped)
    }
    
    func test_newMeetingSheet_initialization() throws {
        let sheet = NewMeetingSheet(viewModel: setupVM)
        XCTAssertNotNil(sheet)
    }
    
    func test_scheduleMeetingView_initialization() throws {
        let view = ScheduleMeetingView(viewModel: setupVM)
        XCTAssertNotNil(view)
    }
    
    func test_meetingTemplatePicker_selection() throws {
        var selected: MeetingTemplate? = nil
        let picker = MeetingTemplatePicker(
            templates: setupVM.availableTemplates,
            selectedTemplate: setupVM.selectedTemplate,
            onSelect: { selected = $0 }
        )
        
        XCTAssertNotNil(picker)
        XCTAssertEqual(picker.templates.count, 5)
        
        if let first = picker.templates.first {
            picker.onSelect(first)
            XCTAssertEqual(selected?.name, first.name)
        }
    }
    
    func test_audioImportView_initialization() throws {
        let view = AudioImportView(viewModel: setupVM)
        XCTAssertNotNil(view)
    }
}
