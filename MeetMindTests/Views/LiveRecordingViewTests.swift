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
    
    func test_liveRecordingHeaderView_configuration() throws {
        var didDismiss = false
        var title = "Sprint Review"
        let titleBinding = Binding(get: { title }, set: { title = $0 })
        let header = LiveRecordingHeaderView(
            title: titleBinding,
            isOfflineFallback: false,
            onDismiss: { didDismiss = true }
        )
        XCTAssertNotNil(header)
        XCTAssertEqual(header.title, "Sprint Review")
        XCTAssertFalse(header.isOfflineFallback)
        header.onDismiss()
        XCTAssertTrue(didDismiss)
    }
    
    func test_waveformVisualizerView_rendering() throws {
        let levels: [Float] = [0.1, 0.4, 0.8, 0.9, 0.5]
        let visualizer = WaveformVisualizerView(levels: levels, isRecording: true)
        XCTAssertNotNil(visualizer)
        XCTAssertEqual(visualizer.levels.count, 5)
        XCTAssertTrue(visualizer.isRecording)
    }
    
    func test_liveTranscriptScrollView_rendering() throws {
        let segments = [
            LiveTranscriptSegmentItem(speakerName: "Alice", text: "Welcome everyone", startTime: 0.0, endTime: 3.5),
            LiveTranscriptSegmentItem(speakerName: "Bob", text: "Thanks Alice", startTime: 3.6, endTime: 6.0)
        ]
        let scroll = LiveTranscriptScrollView(segments: segments, interimText: "Let's review the roadmap")
        XCTAssertNotNil(scroll)
        XCTAssertEqual(scroll.segments.count, 2)
        XCTAssertEqual(scroll.interimText, "Let's review the roadmap")
    }
    
    func test_liveSpeakerSwitcherBar_selection() throws {
        let speakers = [
            SpeakerItem(name: "Alice", colorHex: "#3B82F6"),
            SpeakerItem(name: "Bob", colorHex: "#10B981")
        ]
        var selectedSpeaker: String? = nil
        let bar = LiveSpeakerSwitcherBar(
            speakers: speakers,
            activeSpeakerName: "Alice",
            onSelectSpeaker: { selectedSpeaker = $0.name },
            onAddSpeaker: {}
        )
        XCTAssertNotNil(bar)
        XCTAssertEqual(bar.speakers.count, 2)
        XCTAssertEqual(bar.activeSpeakerName, "Alice")
        bar.onSelectSpeaker(speakers[1])
        XCTAssertEqual(selectedSpeaker, "Bob")
    }
    
    func test_liveActionToolDock_actions() throws {
        var didNote = false
        var didBookmark = false
        var didPhoto = false
        let dock = LiveActionToolDock(
            bookmarkCount: 2,
            isBookmarkHighlighted: false,
            notesCount: 3,
            photosCount: 1,
            onBookmarkTap: { didBookmark = true },
            onNoteTap: { didNote = true },
            onPhotoTap: { didPhoto = true }
        )
        XCTAssertNotNil(dock)
        XCTAssertEqual(dock.notesCount, 3)
        XCTAssertFalse(dock.isBookmarkHighlighted)
        
        dock.onNoteTap()
        XCTAssertTrue(didNote)
        dock.onBookmarkTap()
        XCTAssertTrue(didBookmark)
        dock.onPhotoTap()
        XCTAssertTrue(didPhoto)
    }
    
    func test_recordingControlBarView_callbacks() throws {
        var didToggle = false
        var didStop = false
        var didDiscard = false
        let controls = RecordingControlBarView(
            isPaused: false,
            onDiscard: { didDiscard = true },
            onTogglePauseResume: { didToggle = true },
            onStop: { didStop = true }
        )
        XCTAssertNotNil(controls)
        XCTAssertFalse(controls.isPaused)
        
        controls.onTogglePauseResume()
        XCTAssertTrue(didToggle)
        controls.onStop()
        XCTAssertTrue(didStop)
        controls.onDiscard()
        XCTAssertTrue(didDiscard)
    }
}
