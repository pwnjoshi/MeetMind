import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class RecordingToSummaryE2ETests: XCTestCase {
    func testRecordingStopPersistsAudioReferenceAndDuration() async throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Capture", status: .recording)
        store.mainContext.insert(meeting)
        let audio = MockAudioRecordingService()
        // The saved duration comes from validating the stopped file, not from the recorder's running
        // counter, so the mock must write a file that is actually 12 seconds long.
        audio.canonicalFrameCount = 12 * 44_100
        let recording = LiveRecordingViewModel(meeting: meeting, modelContext: store.mainContext, recordingService: audio)
        recording.startSession()
        try await recording.waitUntilRecordingStarted()
        audio.currentDuration = 12
        let url = try await recording.finishSession()
        XCTAssertEqual(meeting.audioFileURL, url)
        XCTAssertEqual(meeting.duration, 12, accuracy: 0.1)
        XCTAssertEqual(meeting.status, .processing)
        XCTAssertEqual(audio.state, .stopped)
    }
    func testRecordingFailureIsVisibleAndDoesNotPretendToRecord() async {
        let audio = MockAudioRecordingService()
        audio.shouldThrowError = .permissionDenied
        let recording = LiveRecordingViewModel(recordingService: audio)
        recording.startSession()
        do { try await recording.waitUntilRecordingStarted(); XCTFail("Must report denied permission") }
        catch { XCTAssertFalse(recording.isRecording); XCTAssertNotNil(recording.errorMessage) }
    }
}
