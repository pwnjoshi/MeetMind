import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingRecordTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            Meeting.self, TranscriptSegment.self, Speaker.self, Summary.self,
            ActionItem.self, Note.self, Tag.self, Folder.self
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Decision deciders

    func testDeciderRoundTripAndPadding() {
        var record = MeetingRecordData()
        let id = UUID()
        record.setDecider(id, at: 2)
        XCTAssertNil(record.decider(at: 0))
        XCTAssertEqual(record.decider(at: 2), id)
        record.setDecider(nil, at: 2)
        XCTAssertNil(record.decider(at: 2))
    }

    func testRemoveDecisionShiftsFollowingDeciders() {
        var record = MeetingRecordData()
        let first = UUID()
        let second = UUID()
        record.setDecider(first, at: 0)
        record.setDecider(second, at: 1)
        record.removeDecision(at: 0)
        XCTAssertEqual(record.decider(at: 0), second)
        XCTAssertNil(record.decider(at: 1))
    }

    func testRemapKeepsPeopleOnlyForUnchangedText() {
        var record = MeetingRecordData()
        let a = UUID()
        let b = UUID()
        record.setDecider(a, at: 0)
        record.setDecider(b, at: 1)
        record.remapDeciders(oldDecisions: ["Launch 20 Nov", "Budget waits"],
                             newDecisions: ["Budget waits", "Hire designer", "Launch 20 Nov"])
        XCTAssertEqual(record.decider(at: 0), b)
        XCTAssertNil(record.decider(at: 1))
        XCTAssertEqual(record.decider(at: 2), a)
    }

    // MARK: - Store

    func testStorePersistsKeepPrivateSharesAndDeciders() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRecordTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let meetingID = UUID()
        let personID = UUID()
        let entry = SharedMinutesEntry(
            channel: .mail,
            recipients: [SharedMinutesRecipient(name: "Pawan Joshi", email: "pawan@studio.example", colorHex: "#FF9500")],
            subject: "October planning", bodyText: "DISCUSSION:\n Launch 20 Nov\n")

        let store = MeetingRecordStore(fileURL: url)
        try store.update(meetingID) {
            $0.keptPrivate = true
            $0.shares.append(entry)
            $0.setDecider(personID, at: 0)
        }

        let reloaded = MeetingRecordStore(fileURL: url).record(for: meetingID)
        XCTAssertTrue(reloaded.keptPrivate)
        XCTAssertEqual(reloaded.shares, [entry])
        XCTAssertEqual(reloaded.decider(at: 0), personID)
        XCTAssertFalse(MeetingRecordStore(fileURL: url).record(for: UUID()).keptPrivate)
    }

    func testRecipientSummaryUsesFirstNamesWithoutTitles() {
        let entry = SharedMinutesEntry(
            channel: .mail,
            recipients: [
                SharedMinutesRecipient(name: "Dr. Sachin Ghai", email: nil, colorHex: "#30B0C7"),
                SharedMinutesRecipient(name: "Pawan Joshi", email: nil, colorHex: "#FF9500"),
                SharedMinutesRecipient(name: "Garima Pant", email: nil, colorHex: "#AF52DE")
            ],
            subject: "S", bodyText: "")
        XCTAssertEqual(entry.recipientSummary, "Sachin, Pawan and Garima")
        XCTAssertEqual(MeetingRecordFormatting.joinedNames(["A", "B"]), "A and B")
        XCTAssertEqual(MeetingRecordFormatting.joinedNames([]), "")
    }

    // MARK: - People

    private func makeMeeting() -> (meeting: Meeting, voice1: Speaker, voice2: Speaker, pawan: Speaker) {
        let meeting = Meeting(title: "October planning")
        context.insert(meeting)
        let pawan = Speaker(name: "Pawan Joshi", email: "pawan@studio.example")
        context.insert(pawan)
        meeting.addParticipant(pawan)
        var voices: [Speaker] = []
        for (index, text) in ["Let's start with timing.", "I'll update the checklist."].enumerated() {
            let voice = Speaker(name: "Speaker \(index + 1)")
            voice.recordingVoiceLabel = "Speaker \(index + 1)"
            context.insert(voice)
            meeting.addParticipant(voice)
            let segment = TranscriptSegment(text: text, startTime: Double(index) * 10, endTime: Double(index) * 10 + 5, speaker: voice)
            context.insert(segment)
            meeting.addTranscriptSegment(segment)
            voices.append(voice)
        }
        return (meeting, voices[0], voices[1], pawan)
    }

    func testVoicesListUnnamedSpeakersInOrder() {
        let fixture = makeMeeting()
        let rows = MeetingPeopleEditor.voices(in: fixture.meeting, record: MeetingRecordData())
        XCTAssertEqual(rows.map(\.label), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(rows.first?.sampleText, "Let's start with timing.")
        XCTAssertNil(rows.first?.assignedPersonID)
    }

    func testAssignMovesSegmentsAndKeepsRowForUndo() throws {
        let fixture = makeMeeting()
        let store = MeetingRecordStore(fileURL: nil)
        let row = try XCTUnwrap(MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id)).first)

        try MeetingPeopleEditor.assign(row, to: fixture.pawan, meeting: fixture.meeting, context: context, store: store)

        let first = try XCTUnwrap(fixture.meeting.orderedTranscriptSegments.first)
        XCTAssertEqual(first.speaker?.id, fixture.pawan.id)
        XCTAssertFalse(fixture.meeting.participants.contains(where: { $0.id == fixture.voice1.id }))
        let rows = MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id))
        XCTAssertEqual(rows.first?.label, "Speaker 1")
        XCTAssertEqual(rows.first?.assignedPersonID, fixture.pawan.id)

        let assigned = try XCTUnwrap(rows.first)
        try MeetingPeopleEditor.keepUnknown(assigned, meeting: fixture.meeting, context: context, store: store)
        let restored = MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id))
        XCTAssertNil(restored.first?.assignedPersonID)
        XCTAssertEqual(fixture.meeting.orderedTranscriptSegments.first?.speaker?.name, "Speaker 1")
        XCTAssertEqual(fixture.meeting.namedAttendees.map(\.name), ["Pawan Joshi"])
    }

    func testRenameCreatesNamedPersonAndRejectsEmptyName() throws {
        let fixture = makeMeeting()
        let store = MeetingRecordStore(fileURL: nil)
        let row = try XCTUnwrap(MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id)).first)

        XCTAssertThrowsError(try MeetingPeopleEditor.rename(row, to: "  ", meeting: fixture.meeting, context: context, store: store))
        try MeetingPeopleEditor.rename(row, to: "Vaishnavi Shukla", meeting: fixture.meeting, context: context, store: store)

        XCTAssertTrue(fixture.meeting.namedAttendees.contains(where: { $0.name == "Vaishnavi Shukla" }))
        XCTAssertEqual(fixture.meeting.orderedTranscriptSegments.first?.speaker?.name, "Vaishnavi Shukla")
    }

    func testMergeMovesSegmentsToTargetVoice() throws {
        let fixture = makeMeeting()
        let store = MeetingRecordStore(fileURL: nil)
        let rows = MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id))
        XCTAssertEqual(rows.count, 2)

        try MeetingPeopleEditor.merge(rows[1], into: rows[0], meeting: fixture.meeting, context: context, store: store)

        let remaining = MeetingPeopleEditor.voices(in: fixture.meeting, record: store.record(for: fixture.meeting.id))
        XCTAssertEqual(remaining.map(\.label), ["Speaker 1"])
        XCTAssertEqual(remaining.first?.segmentIDs.count, 2)
        XCTAssertTrue(fixture.meeting.transcriptSegments.allSatisfy { $0.speaker?.id == fixture.voice1.id })
    }

    func testSetAbsentPersistsAndCanBeUndone() throws {
        let fixture = makeMeeting()
        try MeetingPeopleEditor.setAbsent(true, person: fixture.pawan, meeting: fixture.meeting, context: context)
        XCTAssertTrue(MeetingPeopleEditor.isAbsent(fixture.pawan, in: fixture.meeting))
        try MeetingPeopleEditor.setAbsent(false, person: fixture.pawan, meeting: fixture.meeting, context: context)
        XCTAssertFalse(MeetingPeopleEditor.isAbsent(fixture.pawan, in: fixture.meeting))
    }
}
