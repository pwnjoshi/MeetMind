import XCTest
import Foundation
import SwiftData
import OfflineEngineKit
@testable import MeetMind

/// Naming a voice must stick: every line, action and later re-analysis uses the person's name,
/// and "Unknown Speaker" only appears for lines that really have no speaker.
@MainActor
final class SpeakerNamingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: MeetingRecordStore!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        store = MeetingRecordStore(fileURL: nil)
    }

    override func tearDown() async throws {
        store = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    private struct Fixture {
        let meeting: Meeting
        let first: Speaker
        let second: Speaker
    }

    private func voice(_ label: String) -> Speaker {
        let speaker = Speaker(name: label, avatarColorHex: "#8E8E93")
        speaker.recordingVoiceLabel = label
        context.insert(speaker)
        return speaker
    }

    private func line(_ text: String, _ start: Double, _ end: Double, _ speaker: Speaker?, in meeting: Meeting, index: Int) {
        let segment = TranscriptSegment(text: text, startTime: start, endTime: end, speaker: speaker,
                                        meeting: nil, sequenceIndex: index)
        context.insert(segment)
        meeting.addTranscriptSegment(segment)
    }

    private func makeFixture() throws -> Fixture {
        let meeting = Meeting(title: "Budget sync", duration: 60, status: .completed)
        context.insert(meeting)
        let first = voice("Speaker 1")
        let second = voice("Speaker 2")
        meeting.addParticipant(first)
        meeting.addParticipant(second)
        line("Let us start with the budget.", 0, 4, first, in: meeting, index: 0)
        line("I think we are over by ten percent.", 5, 10, second, in: meeting, index: 1)
        line("Then I will update the forecast.", 11, 15, first, in: meeting, index: 2)
        try context.save()
        return Fixture(meeting: meeting, first: first, second: second)
    }

    private func row(_ label: String, in meeting: Meeting) throws -> MeetingVoiceRow {
        let rows = MeetingPeopleEditor.voices(in: meeting, record: store.record(for: meeting.id))
        return try XCTUnwrap(rows.first { $0.label == label })
    }

    // MARK: Assigning a voice

    func test_assign_repointsEverySegmentActionAndKeepsNoUnknownSpeaker() throws {
        let fixture = try makeFixture()
        let meeting = fixture.meeting
        let item = ActionItem(title: "Update forecast", assignee: fixture.first)
        context.insert(item)
        meeting.addActionItem(item)
        let maya = Speaker(name: "Maya Rao", avatarColorHex: "#FF9500")
        context.insert(maya)

        try MeetingPeopleEditor.assign(try row("Speaker 1", in: meeting), to: maya, meeting: meeting,
                                       context: context, store: store)

        let ordered = meeting.orderedTranscriptSegments
        XCTAssertEqual(ordered.map(\.speakerDisplayName), ["Maya Rao", "Speaker 2", "Maya Rao"])
        XCTAssertFalse(ordered.contains { $0.speaker == nil })
        XCTAssertEqual(item.assignee?.id, maya.id)
        XCTAssertEqual(item.assignee?.displayName, "Maya Rao")
        XCTAssertTrue(meeting.namedAttendees.contains { $0.id == maya.id })
        XCTAssertFalse(meeting.participants.contains { $0.name == "Speaker 1" })
        XCTAssertEqual(store.record(for: meeting.id).voiceAssignments.map(\.label), ["Speaker 1"])
    }

    // MARK: Re-running analysis

    /// Re-running analysis recreated "Speaker 1" and dropped the named person, so the
    /// transcript showed the raw voice label again.
    func test_replaceTranscript_mapsAssignedLabelBackToPerson() throws {
        let fixture = try makeFixture()
        let meeting = fixture.meeting
        let maya = Speaker(name: "Maya Rao", avatarColorHex: "#FF9500")
        context.insert(maya)
        try MeetingPeopleEditor.assign(try row("Speaker 1", in: meeting), to: maya, meeting: meeting,
                                       context: context, store: store)

        let turns = [
            AnalysisTurn(id: "t0", text: "Let us start with the budget.", start: 0, end: 4, speaker: "Speaker 1"),
            AnalysisTurn(id: "t1", text: "We are over by ten percent.", start: 5, end: 10, speaker: "Speaker 2"),
            AnalysisTurn(id: "t2", text: "I will update the forecast.", start: 11, end: 15, speaker: "Speaker 1"),
            AnalysisTurn(id: "t3", text: "Thanks.", start: 16, end: 17, speaker: nil)
        ]
        MeetingPeopleEditor.replaceTranscript(of: meeting, with: turns, context: context, store: store)
        try context.save()

        let ordered = meeting.orderedTranscriptSegments
        XCTAssertEqual(ordered.count, 4)
        XCTAssertEqual(ordered[0].speaker?.id, maya.id)
        XCTAssertEqual(ordered[2].speaker?.id, maya.id)
        XCTAssertEqual(ordered[1].speaker?.recordingVoiceLabel, "Speaker 2")
        XCTAssertEqual(ordered[1].speakerDisplayName, "Speaker 2")
        XCTAssertEqual(ordered[3].speakerDisplayName, "Unknown Speaker")
        XCTAssertFalse(meeting.participants.contains { $0.name == "Speaker 1" })

        let assignment = try XCTUnwrap(store.record(for: meeting.id).voiceAssignments.first)
        XCTAssertEqual(Set(assignment.segmentIDs), Set([ordered[0].id, ordered[2].id]))
        let voices = MeetingPeopleEditor.voices(in: meeting, record: store.record(for: meeting.id))
        let assigned = try XCTUnwrap(voices.first { $0.label == "Speaker 1" })
        XCTAssertEqual(assigned.assignedPersonID, maya.id)
    }

    func test_replaceTranscript_withoutAssignmentsKeepsSharedVoiceSpeakers() throws {
        let fixture = try makeFixture()
        let turns = [
            AnalysisTurn(id: "a", text: "One", start: 0, end: 2, speaker: "Speaker 1"),
            AnalysisTurn(id: "b", text: "Two", start: 3, end: 5, speaker: "Speaker 1")
        ]
        MeetingPeopleEditor.replaceTranscript(of: fixture.meeting, with: turns, context: context, store: store)
        let speakers = fixture.meeting.orderedTranscriptSegments.compactMap(\.speaker)
        XCTAssertEqual(speakers.count, 2)
        XCTAssertEqual(speakers[0].id, speakers[1].id)
        XCTAssertEqual(speakers[0].id, fixture.first.id)
    }

    // MARK: Display names

    func test_speakerNames_resolveAssignedAndUnnamedLabels() throws {
        let fixture = try makeFixture()
        let maya = Speaker(name: "Maya Rao")
        context.insert(maya)
        fixture.meeting.addParticipant(maya)
        var record = MeetingRecordData()
        record.voiceAssignments = [VoiceAssignment(label: "Speaker 1", personID: maya.id, segmentIDs: [])]

        let names = MeetingSpeakerNames(meeting: fixture.meeting, record: record)
        XCTAssertEqual(names.name(forLabel: "Speaker 1"), "Maya Rao")
        XCTAssertEqual(names.name(forLabel: "Speaker 2"), "Speaker 2")
        XCTAssertEqual(names.name(forLabel: nil), "Unknown Speaker")
        XCTAssertEqual(names.name(forLabel: "  "), "Unknown Speaker")
    }

    func test_speakerDisplayName_onlyUnknownWhenUnassigned() {
        XCTAssertEqual(Speaker(name: "Dev Patel").displayName, "Dev Patel")
        XCTAssertEqual(Speaker(name: "   ").displayName, "Unknown Speaker")
        XCTAssertEqual(Speaker.displayName(of: nil), "Unknown Speaker")
        let segment = TranscriptSegment(text: "Hi", startTime: 0, endTime: 1)
        XCTAssertEqual(segment.speakerDisplayName, "Unknown Speaker")
    }

    func test_fullTranscriptText_usesDisplayNames() throws {
        let fixture = try makeFixture()
        let maya = Speaker(name: "Maya Rao")
        context.insert(maya)
        try MeetingPeopleEditor.assign(try row("Speaker 1", in: fixture.meeting), to: maya,
                                       meeting: fixture.meeting, context: context, store: store)
        XCTAssertTrue(fixture.meeting.fullTranscriptText.contains("Maya Rao: Let us start"))
        XCTAssertFalse(fixture.meeting.fullTranscriptText.contains("Speaker 1"))
    }
}
