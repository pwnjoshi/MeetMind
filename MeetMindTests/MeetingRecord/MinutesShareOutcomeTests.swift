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
        XCTAssertEqual(mail?.recipients.count, 2)
        XCTAssertEqual(mail?.message, "Pawan and Garima have the minutes and their action items.")

        let shared = MinutesSentState.make(outcome: .shared, recipients: people)
        XCTAssertEqual(shared?.title, "Minutes Shared")
        XCTAssertEqual(shared?.recipients.count, 0, "A generic activity never names recipients")
    }

    func testSuccessCopyJoinsNamesNaturally() {
        XCTAssertEqual(MinutesSentState.sentMessage(firstNames: ["Maya", "Arjun", "Pawan", "Garima"]),
                       "Maya, Arjun, Pawan and Garima have the minutes and their action items.")
        XCTAssertEqual(MinutesSentState.sentMessage(firstNames: ["Maya", "Arjun"]),
                       "Maya and Arjun have the minutes and their action items.")
        XCTAssertEqual(MinutesSentState.sentMessage(firstNames: ["Maya"]),
                       "Maya has the minutes and the action items.")
        XCTAssertEqual(MinutesSentState.sentMessage(firstNames: ["A", "B", "C", "D", "E", "F"]),
                       "A, B, C and 3 others have the minutes and their action items.")
        XCTAssertEqual(MinutesSentState.sentMessage(firstNames: []),
                       "The minutes and their action items are on their way.")
    }

    func testSharedCopyDoesNotClaimDeliveryToAnyone() {
        let shared = MinutesSentState.make(outcome: .shared, recipients: [])
        let text = [shared?.title, shared?.message].compactMap { $0 }.joined(separator: " ").lowercased()
        XCTAssertFalse(text.contains("sent"))
        XCTAssertFalse(text.contains("delivered"))
        XCTAssertFalse(text.contains("have the minutes"))
    }

    func testNonSentMailResultsStayInTheSheetWithAnHonestNote() {
        XCTAssertNil(MinutesShareOutcome.fromMail(.saved, error: nil).recordedChannel)
        XCTAssertNil(MinutesShareOutcome.fromMail(.cancelled, error: nil).recordedChannel)
        XCTAssertNil(MinutesShareOutcome.fromMail(.failed, error: nil).recordedChannel)
        XCTAssertEqual(MinutesShareOutcome.mailSaved.sendSheetNotice(viaMail: true),
                       "Saved as a draft in Mail. The minutes have not been sent.")
        XCTAssertEqual(MinutesShareOutcome.cancelled.sendSheetNotice(viaMail: true), "Not sent. Tap Send to try again.")
        XCTAssertNil(MinutesShareOutcome.cancelled.sendSheetNotice(viaMail: false))
        XCTAssertTrue(MinutesShareOutcome.failed("Mail could not send the minutes.")
            .sendSheetNotice(viaMail: true)?.hasSuffix("Nothing was sent.") ?? false)
        XCTAssertNil(MinutesShareOutcome.mailSent.sendSheetNotice(viaMail: true))
    }

    func testSendButtonLabelAndState() {
        XCTAssertEqual(MinutesSendPlan.buttonTitle(count: 4), "Send to 4 People")
        XCTAssertEqual(MinutesSendPlan.buttonTitle(count: 1), "Send to 1 Person")
        XCTAssertEqual(MinutesSendPlan.buttonTitle(count: 0), "Send Minutes")
        XCTAssertEqual(MinutesSendPlan.buttonTitle(count: 3, mailAvailable: false), "Share PDF")
        XCTAssertEqual(MinutesSendPlan.accessibilityLabel(count: 4), "Send to 4 people")
        XCTAssertEqual(MinutesSendPlan.accessibilityLabel(count: 1), "Send to 1 person")

        XCTAssertNil(MinutesSendPlan.disabledReason(candidateCount: 4, selectedCount: 4, isPreparing: false))
        XCTAssertNotNil(MinutesSendPlan.disabledReason(candidateCount: 0, selectedCount: 0, isPreparing: false))
        XCTAssertEqual(MinutesSendPlan.disabledReason(candidateCount: 4, selectedCount: 0, isPreparing: false),
                       "Select at least one person.")
        XCTAssertNotNil(MinutesSendPlan.disabledReason(candidateCount: 4, selectedCount: 4, isPreparing: true))
        XCTAssertNil(MinutesSendPlan.disabledReason(candidateCount: 0, selectedCount: 0, isPreparing: false,
                                                    mailAvailable: false))
    }

    func testRecipientsDefaultToEveryAttendeeWithAnEmail() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let me = Speaker(name: "Me User", email: "me@studio.example")
        let maya = Speaker(name: "Maya Rao", email: "maya@studio.example")
        let duplicate = Speaker(name: "Maya R", email: " MAYA@studio.example ")
        let noEmail = Speaker(name: "Arjun Mehta", email: nil)
        let blank = Speaker(name: "Pawan Joshi", email: "  ")
        let garima = Speaker(name: "Garima Pant", email: "garima@studio.example")
        for person in [me, maya, duplicate, noEmail, blank, garima] { container.mainContext.insert(person) }

        let result = MinutesSendPlan.candidates(from: [me, maya, duplicate, noEmail, blank, garima], userName: "Me User")
        XCTAssertEqual(result.map(\.name), ["Maya Rao", "Garima Pant"])
        XCTAssertEqual(MinutesSendPlan.defaultSelection(result), Set(result.map(\.id)))
        XCTAssertTrue(MinutesSendPlan.defaultSelection([]).isEmpty)
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
