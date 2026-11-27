import XCTest
import Foundation
@testable import MeetMind

@MainActor
final class MinutesApprovalTests: XCTestCase {
    private func input(finalizing: Bool = false, participants: Int = 2, unnamed: Int = 0, pending: Int = 0) -> ApprovalChecklistInput {
        ApprovalChecklistInput(minutesNeedFinalization: finalizing, participantCount: participants,
                               unnamedSpeakerCount: unnamed, pendingTaskSuggestionCount: pending)
    }

    func testAllChecksPassWhenReady() {
        let checklist = ApprovalChecklist.evaluate(input())
        XCTAssertFalse(checklist.requiresReview)
        XCTAssertEqual(checklist.checks.count, 3)
        XCTAssertTrue(checklist.failedChecks.isEmpty)
    }

    func testUnfinalizedMinutesRequireReview() {
        let checklist = ApprovalChecklist.evaluate(input(finalizing: true))
        XCTAssertTrue(checklist.requiresReview)
        XCTAssertEqual(checklist.failedChecks.map { $0.kind }, [.minutesFinalized])
    }

    func testUnnamedSpeakersAndPendingTasksFail() {
        let checklist = ApprovalChecklist.evaluate(input(unnamed: 2, pending: 3))
        XCTAssertEqual(checklist.failedChecks.map { $0.kind }, [.speakersNamed, .tasksReviewed])
        XCTAssertTrue(checklist.failedChecks[0].detail.contains("2 speakers"))
        XCTAssertTrue(checklist.failedChecks[1].detail.contains("3 suggested tasks"))
    }

    func testNoSavedSpeakersFailsSpeakerCheck() {
        let checklist = ApprovalChecklist.evaluate(input(participants: 0))
        XCTAssertEqual(checklist.failedChecks.map { $0.kind }, [.speakersNamed])
    }

    func testMinutesTextContainsSectionsAndDisclaimer() {
        let text = MinutesApprovalText.build(ApprovalMinutesInput(
            title: "Planning", date: Date(timeIntervalSince1970: 0), attendees: ["Asha", "Ravi"],
            summary: "We planned the launch.", decisions: ["Launch in November"],
            actions: [SeriesActionSnapshot(title: "Send invoice", owner: "Asha", isCompleted: false)]))
        XCTAssertTrue(text.contains("Minutes: Planning"))
        XCTAssertTrue(text.contains("Attendees: Asha, Ravi"))
        XCTAssertTrue(text.contains("- Launch in November"))
        XCTAssertTrue(text.contains("- [ ] Send invoice (Asha)"))
        XCTAssertTrue(text.contains("not approved until the reviewer replies"))
    }

    func testVersionTagIsStableAndSensitiveToText() {
        XCTAssertEqual(MinutesApprovalText.versionTag(for: "a"), MinutesApprovalText.versionTag(for: "a"))
        XCTAssertNotEqual(MinutesApprovalText.versionTag(for: "a"), MinutesApprovalText.versionTag(for: "b"))
        XCTAssertEqual(MinutesApprovalText.versionTag(for: "a").count, 8)
    }

    func testStorePersistsRecordsPerMeeting() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinutesApprovalTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("approvals.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meetingA = UUID()
        let meetingB = UUID()
        let first = MinutesApprovalRecord(meetingID: meetingA, reviewerName: "Asha", reviewerEmail: "asha@example.com",
                                          sentAt: Date(timeIntervalSince1970: 1_700_000_000), channel: .mail, versionTag: "abcd1234")
        let second = MinutesApprovalRecord(meetingID: meetingA, reviewerName: "Ravi", reviewerEmail: nil,
                                           sentAt: Date(timeIntervalSince1970: 1_700_000_500), channel: .shareSheet, versionTag: "abcd1234")

        let store = MinutesApprovalStore(fileURL: url)
        store.add(first)
        store.add(second)
        XCTAssertNil(store.lastSaveError)

        let reloaded = MinutesApprovalStore(fileURL: url)
        XCTAssertEqual(reloaded.records(for: meetingA), [second, first])
        XCTAssertTrue(reloaded.records(for: meetingB).isEmpty)
    }
}
