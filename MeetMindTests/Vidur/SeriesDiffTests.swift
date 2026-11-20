import XCTest
import Foundation
@testable import MeetMind

final class SeriesDiffTests: XCTestCase {
    private let earlierID = UUID()
    private let laterID = UUID()

    private func earlier(
        decisions: [String] = [], actions: [SeriesActionSnapshot] = [], agenda: [String] = [],
        attendees: [String] = [], absent: [String] = []
    ) -> SeriesMeetingSnapshot {
        SeriesMeetingSnapshot(id: earlierID, title: "October planning", date: Date(timeIntervalSince1970: 1_000),
                              decisions: decisions, actions: actions, agenda: agenda,
                              attendees: attendees, absent: absent)
    }

    private func later(
        decisions: [String] = [], actions: [SeriesActionSnapshot] = [], agenda: [String] = [],
        attendees: [String] = [], absent: [String] = []
    ) -> SeriesMeetingSnapshot {
        SeriesMeetingSnapshot(id: laterID, title: "Product planning", date: Date(timeIntervalSince1970: 2_000),
                              decisions: decisions, actions: actions, agenda: agenda,
                              attendees: attendees, absent: absent)
    }

    func testNormalizeIgnoresCaseAndPunctuation() {
        XCTAssertEqual(SeriesDiffEngine.normalize("  Ship the Beta, now! "), "ship the beta now")
    }

    func testDecisionsNewAndNotRepeatedCiteTheirMeeting() {
        let diff = SeriesDiffEngine.compare(
            earlier(decisions: ["Launch on 20 November", "Hire a designer"]),
            later(decisions: ["launch on 20 november.", "Wait for the Finance estimate"]))
        XCTAssertEqual(diff.decisionsNew.map { $0.text }, ["Wait for the Finance estimate"])
        XCTAssertEqual(diff.decisionsNew.first?.meetingID, laterID)
        XCTAssertEqual(diff.decisionsNotRepeated.map { $0.text }, ["Hire a designer"])
        XCTAssertEqual(diff.decisionsNotRepeated.first?.meetingID, earlierID)
    }

    func testActionItemsNewClosedCarriedAndNotListed() {
        let diff = SeriesDiffEngine.compare(
            earlier(actions: [
                SeriesActionSnapshot(title: "Send invoice", owner: "Asha", isCompleted: false),
                SeriesActionSnapshot(title: "Book venue", owner: nil, isCompleted: false),
                SeriesActionSnapshot(title: "Draft brief", owner: nil, isCompleted: false),
                SeriesActionSnapshot(title: "Old done item", owner: nil, isCompleted: true)
            ]),
            later(actions: [
                SeriesActionSnapshot(title: "send invoice", owner: "Asha", isCompleted: true),
                SeriesActionSnapshot(title: "Book venue", owner: nil, isCompleted: false),
                SeriesActionSnapshot(title: "Order swag", owner: "Ravi", isCompleted: false)
            ]))
        XCTAssertEqual(diff.actionsClosed.map { $0.text }, ["send invoice"])
        XCTAssertEqual(diff.actionsCarried.map { $0.text }, ["Book venue"])
        XCTAssertEqual(diff.actionsNew.map { $0.text }, ["Order swag"])
        XCTAssertEqual(diff.actionsNew.first?.detail, "Owner: Ravi")
        XCTAssertEqual(diff.actionsNotListed.map { $0.text }, ["Draft brief"])
        XCTAssertEqual(diff.stillOpenCount, 1)
    }

    func testAgendaItemsStripListMarkers() {
        let items = SeriesDiffEngine.agendaItems(from: "- Budget\n1. Launch date\n\u{2022} Hiring\n\n2) Risks")
        XCTAssertEqual(items, ["Budget", "Launch date", "Hiring", "Risks"])
        XCTAssertEqual(SeriesDiffEngine.agendaItems(from: nil), [])
    }

    func testAgendaAddedAndRemoved() {
        let diff = SeriesDiffEngine.compare(
            earlier(agenda: ["Budget", "Hiring"]),
            later(agenda: ["budget", "Launch date"]))
        XCTAssertEqual(diff.agendaAdded.map { $0.text }, ["Launch date"])
        XCTAssertEqual(diff.agendaRemoved.map { $0.text }, ["Hiring"])
    }

    func testAttendanceTreatsAbsentParticipantsAsNotPresent() {
        let diff = SeriesDiffEngine.compare(
            earlier(attendees: ["Asha", "Ravi", "Meera"], absent: ["Meera"]),
            later(attendees: ["Asha", "Ravi", "Meera"], absent: ["Ravi"]))
        XCTAssertEqual(diff.attendeesJoined.map { $0.text }, ["Meera"])
        XCTAssertEqual(diff.attendeesLeft.map { $0.text }, ["Ravi"])
    }

    func testArgumentOrderDoesNotMatter() {
        let a = earlier(decisions: ["A"])
        let b = later(decisions: ["B"])
        let forward = SeriesDiffEngine.compare(a, b)
        let reversed = SeriesDiffEngine.compare(b, a)
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.earlier.id, earlierID)
    }

    func testIdenticalMeetingsHaveNoChanges() {
        let diff = SeriesDiffEngine.compare(
            earlier(decisions: ["A"], agenda: ["X"], attendees: ["Asha"]),
            later(decisions: ["A"], agenda: ["X"], attendees: ["Asha"]))
        XCTAssertEqual(diff.changedCount, 0)
        XCTAssertEqual(diff.stillOpenCount, 0)
    }

    func testExtractiveCitationsOnlyQuoteMatchingLines() {
        let meeting = VidurSourceMeeting(id: UUID(), title: "Budget sync", date: Date(), turns: [
            VidurSourceTurn(text: "Lunch is at noon.", start: 5, end: 8, speaker: nil),
            VidurSourceTurn(text: "The budget approval waits for Finance.", start: 62, end: 70, speaker: "Asha")
        ])
        let matches = VidurAnswerService.extractiveCitations(question: "Was the budget approved?", sources: [meeting], limit: 3)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.quote, "The budget approval waits for Finance.")
        XCTAssertEqual(matches.first?.timecode, "01:02")
    }

    func testAnswerWithoutModelIsLabelledAndNeverGenerated() async {
        let meeting = VidurSourceMeeting(id: UUID(), title: "Sync", date: Date(), turns: [
            VidurSourceTurn(text: "We agreed the launch moves to November.", start: 12, end: 20, speaker: nil)
        ])
        let answer = await VidurAnswerService.answer(
            question: "When does the launch move?", sources: [meeting], length: .standard,
            modelIsInstalled: { false })
        XCTAssertEqual(answer.kind, .extractive)
        XCTAssertTrue(answer.notice?.contains("Settings") ?? false)
        XCTAssertEqual(answer.citations.count, 1)
    }

    func testAnswerWithoutModelAndNoMatchIsUnavailable() async {
        let meeting = VidurSourceMeeting(id: UUID(), title: "Sync", date: Date(), turns: [
            VidurSourceTurn(text: "Hello everyone.", start: 0, end: 2, speaker: nil)
        ])
        let answer = await VidurAnswerService.answer(
            question: "Who owns the estimate?", sources: [meeting], length: .brief,
            modelIsInstalled: { false })
        XCTAssertEqual(answer.kind, .unavailable)
        XCTAssertTrue(answer.citations.isEmpty)
    }
}
