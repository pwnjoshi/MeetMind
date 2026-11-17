import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingProcessingViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var pipelineVM: ProcessingPipelineViewModel!
    private var meetingId: UUID!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        meetingId = UUID()
        let meeting = Meeting(id: meetingId, title: "Synthesis Meeting", status: .processing)
        context.insert(meeting)
        pipelineVM = ProcessingPipelineViewModel(meeting: meeting, modelContext: context)
    }
    
    override func tearDownWithError() throws {
        pipelineVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_meetingProcessingView_initialization() throws {
        let view = MeetingProcessingView(meetingId: meetingId, viewModel: pipelineVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.meetingId, meetingId)
    }
    
    func test_processingProgressRingView_rendering() throws {
        let ring = ProcessingProgressRingView(progress: 0.5)
        XCTAssertNotNil(ring)
        XCTAssertEqual(ring.progress, 0.5)
    }
    
    func test_processingStageRowView_states() throws {
        let stage = ProcessingStage(id: 1, name: "Speech Diarization", description: "Transcribing speech", state: .inProgress)
        let row = ProcessingStageRowView(stage: stage)
        XCTAssertNotNil(row)
        XCTAssertEqual(row.stage.name, "Speech Diarization")
        XCTAssertEqual(row.stage.state, .inProgress)
    }
}
