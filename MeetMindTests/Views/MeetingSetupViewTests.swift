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
    
    func test_participantTokenChip_removal() throws {
        let speaker = Speaker(name: "Alice Smith", role: "Product Manager")
        var removed = false
        
        let chip = ParticipantTokenChip(speaker: speaker) {
            removed = true
        }
        
        XCTAssertNotNil(chip)
        XCTAssertEqual(chip.speaker.name, "Alice Smith")
        chip.onRemove()
        XCTAssertTrue(removed)
    }
    
    func test_audioImportView_initialization() throws {
        let view = AudioImportView(viewModel: setupVM)
        XCTAssertNotNil(view)
    }
    
    func test_meetingCardAttendeesView_initialization() throws {
        let speakers = [Speaker(name: "Alice"), Speaker(name: "Bob")]
        let view = MeetingCardAttendeesView(speakers: speakers)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.speakers.count, 2)
    }
    
    func test_meetingCardFooterView_initialization() throws {
        let meeting = Meeting(title: "Architecture Review", duration: 1200)
        let footer = MeetingCardFooterView(meeting: meeting)
        XCTAssertNotNil(footer)
        XCTAssertEqual(footer.meeting.title, "Architecture Review")
    }
    
    func test_audioImportHeaderView_initialization() throws {
        let header = AudioImportHeaderView()
        XCTAssertNotNil(header)
    }
    
    func test_audioImportProgressView_initialization() throws {
        let progress = AudioImportProgressView(message: "Transcribing audio...")
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress.message, "Transcribing audio...")
    }
}
