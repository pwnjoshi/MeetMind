import XCTest
import MessageUI
import SwiftData
@testable import MeetMind

@MainActor
final class MinutesShareOutcomeTests: XCTestCase {
    private struct SampleError: Error {}

    private let people = [
        SharedMinutesRecipient(name: "Pawan Joshi", email: "pawan@studio.example", colorHex: "#FF9500"),
        SharedMinutesRecipient(name: "Garima Pant", email: "garima@studio.example", colorHex: "#AF52DE")
    ]

    func testMailResultsMapToOutcomes() {
        XCTAssertEqual(MinutesShareOutcome.fromMail(.sent, error: nil), .mailSent)
        XCTAssertEqual(MinutesShareOutcome.fromMail(.saved, error: nil), .mailSaved)
        XCTAssertEqual(MinutesShareOutcome.fromMail(.cancelled, error: nil), .cancelled)
        if case .failed = MinutesShareOutcome.fromMail(.failed, error: nil) {} else { XCTFail("failed result must fail") }
        if case .failed = MinutesShareOutcome.fromMail(.sent, error: SampleError()) {} else { XCTFail("error wins over sent") }
    }

    func testActivityCompletionMapsToSharedOrCancelled() {
        XCTAssertEqual(MinutesShareOutcome.fromActivity(completed: true), .shared)
        XCTAssertEqual(MinutesShareOutcome.fromActivity(completed: false), .cancelled)
    }

    func testOnlyMailSentAndSharedRecordHistory() {
        XCTAssertEqual(MinutesShareOutcome.mailSent.recordedChannel, .mail)
        XCTAssertEqual(MinutesShareOutcome.shared.recordedChannel, .shareSheet)
        XCTAssertNil(MinutesShareOutcome.mailSaved.recordedChannel)
        XCTAssertNil(MinutesShareOutcome.cancelled.recordedChannel)
        XCTAssertNil(MinutesShareOutcome.failed("x").recordedChannel)
        XCTAssertEqual(MinutesShareOutcome.failed("boom").errorMessage, "boom")
        XCTAssertNil(MinutesShareOutcome.cancelled.errorMessage)
    }

    func testSentStateOnlyForSentOrShared() {
        XCTAssertNil(MinutesSentState.make(outcome: .cancelled, recipients: people))
        XCTAssertNil(MinutesSentState.make(outcome: .mailSaved, recipients: people))
        XCTAssertNil(MinutesSentState.make(outcome: .failed("x"), recipients: people))

        let mail = MinutesSentState.make(outcome: .mailSent, recipients: people)
        XCTAssertEqual(mail?.title, "Minutes Sent")
        XCTAssertEqual(mail?.settledText, "Sent from Mail")
        XCTAssertEqual(mail?.recipients.count, 2)
        XCTAssertTrue(mail?.message.contains("Pawan and Garima") ?? false)

        let shared = MinutesSentState.make(outcome: .shared, recipients: people)
        XCTAssertEqual(shared?.title, "Minutes Shared")
        XCTAssertEqual(shared?.settledText, "Shared")
        XCTAssertEqual(shared?.recipients.count, 0, "A generic activity never names recipients")
    }

    func testCopyNeverClaimsReceiptOrReading() {
        let states = [MinutesSentState.make(outcome: .mailSent, recipients: people),
                      MinutesSentState.make(outcome: .shared, recipients: [])].compactMap { $0 }
        XCTAssertEqual(states.count, 2)
        for state in states {
            let text = [state.title, state.handoffText, state.settledText, state.message].joined(separator: " ").lowercased()
            XCTAssertFalse(text.contains("delivered"))
            XCTAssertFalse(text.contains("have the minutes"))
            XCTAssertFalse(text.contains("read by"))
        }
    }

    func testFollowUpDraftIsPrefilledFromMeeting() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let context = container.mainContext
        let meeting = Meeting(title: "October planning", createdAt: Date(timeIntervalSince1970: 1_791_979_200),
                              duration: 600, status: .completed)
        context.insert(meeting)
        meeting.seriesID = UUID()
        meeting.seriesName = "Product planning"
        meeting.addParticipant(Speaker(name: "Pawan Joshi", email: "pawan@studio.example"))
        meeting.addParticipant(Speaker(name: "Garima Pant", email: "garima@studio.example"))
        meeting.addActionItem(ActionItem(title: "Send estimate", meeting: meeting))

        let draft = MinutesFollowUpDraft.make(from: meeting, modelContext: context)
        XCTAssertEqual(draft.variant, .followUp)
        XCTAssertEqual(draft.title, "Product planning")
        XCTAssertEqual(draft.scheduledSeriesID, meeting.seriesID)
        XCTAssertTrue(draft.followUpSource === meeting)
        XCTAssertEqual(Set(draft.participants.map(\.name)), ["Pawan Joshi", "Garima Pant"])
        XCTAssertEqual(draft.openActionsToCarry.count, 1)
        XCTAssertTrue(draft.carryOverOpenActions)
    }

    func testFollowUpDraftWithoutSeriesUsesMeetingTitle() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Retro", createdAt: Date(), duration: 60, status: .completed)
        container.mainContext.insert(meeting)
        let draft = MinutesFollowUpDraft.make(from: meeting, modelContext: container.mainContext)
        XCTAssertEqual(draft.title, "Retro follow-up")
        XCTAssertFalse(draft.carryOverOpenActions)
    }
}
