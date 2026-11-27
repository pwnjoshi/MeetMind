import XCTest
import SwiftUI
import SwiftData
@testable import MeetMind

@MainActor
final class LiveRecordingViewTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recordingVM: LiveRecordingViewModel!
    private var meetingId: UUID!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        meetingId = UUID()
        recordingVM = LiveRecordingViewModel(meetingId: meetingId, modelContext: context)
    }
    
    override func tearDownWithError() throws {
        recordingVM = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }
    
    func test_liveRecordingView_initialization() throws {
        let view = LiveRecordingView(meetingId: meetingId, viewModel: recordingVM)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.meetingId, meetingId)
    }
    
    func test_waveformVisualizerView_rendering() throws {
        let levels: [Float] = [0.1, 0.4, 0.8, 0.9, 0.5]
        let visualizer = WaveformVisualizerView(levels: levels, isRecording: true)
        XCTAssertNotNil(visualizer)
        XCTAssertEqual(visualizer.levels.count, 5)
        XCTAssertTrue(visualizer.isRecording)
    }
}
