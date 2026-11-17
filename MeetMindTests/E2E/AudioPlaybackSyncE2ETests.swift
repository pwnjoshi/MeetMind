import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class AudioPlaybackSyncE2ETests: XCTestCase {
    func testTranscriptTapSeeksTheInjectedPlayer() throws {
        let meeting = Meeting(title: "Playback", duration: 180, audioFileURL: URL(fileURLWithPath: "/recording.m4a"))
        let segment = TranscriptSegment(text: "Decision", startTime: 35, endTime: 40)
        meeting.addTranscriptSegment(segment)
        let player = MockAudioPlaybackService()
        let detail = MeetingDetailViewModel(meeting: meeting, playbackService: player)
        detail.tapToSeek(segment: segment)
        XCTAssertEqual(player.currentTime, 35, accuracy: 0.01)
        XCTAssertTrue(player.isPlaying)
        detail.stopPlayback()
        XCTAssertFalse(player.isPlaying)
    }
    func testSeekClampsToMeetingDuration() {
        let player = MockAudioPlaybackService()
        let detail = MeetingDetailViewModel(meeting: Meeting(title: "Bounds", duration: 180), playbackService: player)
        detail.seek(to: 500)
        XCTAssertEqual(detail.currentPlayheadTime, 180)
        detail.seek(to: -10)
        XCTAssertEqual(detail.currentPlayheadTime, 0)
    }
}
