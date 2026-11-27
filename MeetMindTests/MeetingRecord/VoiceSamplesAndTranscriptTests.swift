import XCTest
import Foundation
import SwiftData
import SwiftUI
@testable import MeetMind

/// Voice sample selection, talk-time numbers, and the transcript page's grouping, search and active line.
@MainActor
final class VoiceSamplesAndTranscriptTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func voice(_ label: String) -> Speaker {
        let speaker = Speaker(name: label)
        speaker.recordingVoiceLabel = label
        context.insert(speaker)
        return speaker
    }

    @discardableResult
    private func add(_ text: String, _ start: Double, _ end: Double, _ speaker: Speaker?, to meeting: Meeting,
                     index: Int) -> TranscriptSegment {
        let segment = TranscriptSegment(text: text, startTime: start, endTime: end, speaker: speaker,
                                        meeting: nil, sequenceIndex: index)
        context.insert(segment)
        meeting.addTranscriptSegment(segment)
        return segment
    }

    private func makeMeeting() -> (meeting: Meeting, first: Speaker, second: Speaker) {
        let meeting = Meeting(title: "Roadmap", duration: 120, status: .completed)
        context.insert(meeting)
        let first = voice("Speaker 1")
        let second = voice("Speaker 2")
        meeting.addParticipant(first)
        meeting.addParticipant(second)
        return (meeting, first, second)
    }

    private func firstRow(in meeting: Meeting, label: String) throws -> MeetingVoiceRow {
        let rows = MeetingPeopleEditor.voices(in: meeting, record: MeetingRecordData())
        return try XCTUnwrap(rows.first { $0.label == label })
    }

    // MARK: Voice samples

    func test_samples_areLongDistinctAndSpreadAcrossTheMeeting() throws {
        let setup = makeMeeting()
        add("Too short", 0, 1.5, setup.first, to: setup.meeting, index: 0)
        add("Opening remarks about the plan", 10, 13, setup.first, to: setup.meeting, index: 1)
        add("A long explanation of the budget", 20, 25, setup.first, to: setup.meeting, index: 2)
        add("A reply from the other person", 27, 30, setup.second, to: setup.meeting, index: 3)
        add("Timeline for the launch", 30, 32.5, setup.first, to: setup.meeting, index: 4)
        add("Closing thoughts on hiring", 40, 44, setup.first, to: setup.meeting, index: 5)
        add("Closing thoughts on hiring", 50, 52, setup.first, to: setup.meeting, index: 6)

        let samples = MeetingVoiceSamples.samples(for: try firstRow(in: setup.meeting, label: "Speaker 1"),
                                                  in: setup.meeting)

        XCTAssertEqual(samples.count, 3)
        XCTAssertTrue(samples.allSatisfy { $0.duration >= 2 })
        XCTAssertEqual(samples.map(\.startTime), samples.map(\.startTime).sorted())
        XCTAssertEqual(Set(samples.map(\.text)).count, 3)
        XCTAssertEqual(samples.map(\.startTime), [10, 20, 40])
    }

    func test_samples_fallBackToLongestClipsWhenNothingIsTwoSeconds() throws {
        let setup = makeMeeting()
        add("Yes", 0, 0.6, setup.first, to: setup.meeting, index: 0)
        add("Right, okay", 5, 6.4, setup.first, to: setup.meeting, index: 1)
        add("Agreed", 9, 9.8, setup.first, to: setup.meeting, index: 2)
        add("Fine", 12, 12.5, setup.first, to: setup.meeting, index: 3)

        let samples = MeetingVoiceSamples.samples(for: try firstRow(in: setup.meeting, label: "Speaker 1"),
                                                  in: setup.meeting)
        XCTAssertEqual(samples.count, 3)
        XCTAssertFalse(samples.contains { $0.text == "Fine" })
    }

    func test_stats_countTalkTimeAndTurns() throws {
        let setup = makeMeeting()
        add("One", 0, 4, setup.first, to: setup.meeting, index: 0)
        add("Two", 4, 6, setup.first, to: setup.meeting, index: 1)
        add("Reply", 6, 9, setup.second, to: setup.meeting, index: 2)
        add("Three", 9, 12, setup.first, to: setup.meeting, index: 3)

        let stats = MeetingVoiceSamples.stats(for: try firstRow(in: setup.meeting, label: "Speaker 1"),
                                              in: setup.meeting)
        XCTAssertEqual(stats.talkTime, 9, accuracy: 0.001)
        XCTAssertEqual(stats.turns, 2)
        XCTAssertEqual(stats.summaryText, "9s \u{00B7} 2 turns")
        XCTAssertEqual(MeetingVoiceStats(talkTime: 125, turns: 1).summaryText, "2m 5s \u{00B7} 1 turn")
    }

    func test_samplePlayer_reportsMissingAudioAndStaysStopped() {
        let player = VoiceSamplePlayer()
        let sample = MeetingVoiceSample(id: UUID(), startTime: 1, endTime: 4, text: "Hello")
        player.toggle(sample, audioURL: URL(fileURLWithPath: "/nonexistent/recording.m4a"))
        XCTAssertNil(player.playingSampleID)
        XCTAssertNotNil(player.errorMessage)
        XCTAssertFalse(player.isPlaying(sample))
    }

    // MARK: Transcript turns

    func test_turns_groupConsecutiveLinesBySpeaker() {
        let setup = makeMeeting()
        let a = add("Hello", 0, 2, setup.first, to: setup.meeting, index: 0)
        let b = add("Welcome", 2, 4, setup.first, to: setup.meeting, index: 1)
        let c = add("Thanks", 4, 6, setup.second, to: setup.meeting, index: 2)
        let d = add("Next topic", 6, 8, setup.first, to: setup.meeting, index: 3)

        let turns = TranscriptTurnGrouper.turns(from: setup.meeting.orderedTranscriptSegments)
        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(turns[0].segments.map(\.id), [a.id, b.id])
        XCTAssertEqual(turns[1].segments.map(\.id), [c.id])
        XCTAssertEqual(turns[2].segments.map(\.id), [d.id])
        XCTAssertEqual(turns.map(\.speakerName), ["Speaker 1", "Speaker 2", "Speaker 1"])
        XCTAssertEqual(turns[0].timestampText, "0:00")
    }

    func test_turns_unassignedLinesShowUnknownSpeaker() {
        let setup = makeMeeting()
        add("Who said this", 0, 2, nil, to: setup.meeting, index: 0)
        let turns = TranscriptTurnGrouper.turns(from: setup.meeting.orderedTranscriptSegments)
        XCTAssertEqual(turns.first?.speakerName, "Unknown Speaker")
    }

    func test_search_filtersLinesAndDropsEmptyTurns() {
        let setup = makeMeeting()
        add("The budget is tight", 0, 3, setup.first, to: setup.meeting, index: 0)
        add("Hiring plan", 3, 6, setup.first, to: setup.meeting, index: 1)
        add("More BUDGET talk", 6, 9, setup.second, to: setup.meeting, index: 2)
        let segments = setup.meeting.orderedTranscriptSegments

        let turns = TranscriptTurnGrouper.turns(from: segments, matching: "budget")
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.flatMap(\.segments).map(\.text), ["The budget is tight", "More BUDGET talk"])
        XCTAssertEqual(TranscriptSearch.matchingLineCount(in: segments, query: "budget"), 2)
        XCTAssertEqual(TranscriptTurnGrouper.turns(from: segments, matching: "  ").count, 2)
        XCTAssertTrue(TranscriptTurnGrouper.turns(from: segments, matching: "zebra").isEmpty)
    }

    func test_highlight_marksEveryMatch() {
        let marked = TranscriptSearch.highlighted("Budget and budget again", query: "budget")
        let highlightedRuns = marked.runs.filter { $0.backgroundColor != nil }
        XCTAssertEqual(highlightedRuns.count, 2)
        XCTAssertEqual(String(marked.characters), "Budget and budget again")
    }

    func test_activeSegment_followsPlayheadAndFadesAfterLongSilence() {
        let setup = makeMeeting()
        let a = add("First", 0, 4, setup.first, to: setup.meeting, index: 0)
        let b = add("Second", 5, 9, setup.second, to: setup.meeting, index: 1)
        let segments = setup.meeting.orderedTranscriptSegments

        XCTAssertEqual(TranscriptTurnGrouper.activeSegmentID(at: 1, in: segments), a.id)
        XCTAssertEqual(TranscriptTurnGrouper.activeSegmentID(at: 4.5, in: segments), a.id)
        XCTAssertEqual(TranscriptTurnGrouper.activeSegmentID(at: 6, in: segments), b.id)
        XCTAssertNil(TranscriptTurnGrouper.activeSegmentID(at: 60, in: segments))
    }

    func test_playerBar_speedCyclesThroughOneOnePointFiveTwo() {
        XCTAssertEqual(StickyAudioPlayerBar.nextRate(after: 1.0), 1.5)
        XCTAssertEqual(StickyAudioPlayerBar.nextRate(after: 1.5), 2.0)
        XCTAssertEqual(StickyAudioPlayerBar.nextRate(after: 2.0), 1.0)
        XCTAssertEqual(StickyAudioPlayerBar.nextRate(after: 0.75), 1.0)
        XCTAssertEqual(StickyAudioPlayerBar.rateLabel(1.5), "1.5\u{00D7}")
        XCTAssertEqual(StickyAudioPlayerBar.rateLabel(2.0), "2\u{00D7}")
    }
}
