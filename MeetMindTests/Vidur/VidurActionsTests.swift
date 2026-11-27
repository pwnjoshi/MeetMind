import XCTest
import Foundation
import SwiftData
import OfflineEngineKit
@testable import MeetMind

/// Vidur's commands change data only through the same code the manual screens use,
/// and they never report success that did not happen.
@MainActor
final class VidurActionsTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let made = try ModelContainerFactory.createInMemoryContainer()
        container = made
        return made.mainContext
    }

    func testSchedulingCreatesAScheduledMeetingWithPeople() throws {
        let context = try makeContext()
        let start = Date().addingTimeInterval(86_400)
        let draft = VidurScheduleDraft(title: "Design review", start: start, durationMinutes: 45, people: ["Maya", "Arjun"])
        let result = VidurActions.perform(VidurPendingAction(kind: .schedule(draft)), modelContext: context)
        XCTAssertTrue(result.succeeded, result.message)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(meetings.first?.title, "Design review")
        XCTAssertEqual(meetings.first?.status, .scheduled)
        XCTAssertEqual(Set(meetings.first?.participants.map { $0.name } ?? []), ["Maya", "Arjun"])
        XCTAssertEqual(meetings.first?.duration ?? 0, 2_700, accuracy: 1)
        XCTAssertEqual(result.meetingID, meetings.first?.id)
    }

    func testCompletingAnActionNeedsAMatchAndMarksItDone() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Budget sync", status: .completed)
        context.insert(meeting)
        let item = ActionItem(title: "Send estimate to Finance", meeting: meeting)
        context.insert(item)
        meeting.addActionItem(item)
        try context.save()

        guard case .confirm(let action, _) = VidurActions.prepare(
            .completeAction(query: "estimate"), current: meeting, modelContext: context, isRecording: false) else {
            return XCTFail("Expected a confirmation card")
        }
        XCTAssertFalse(item.isCompleted, "Nothing changes before the user confirms")
        let result = VidurActions.perform(action, modelContext: context)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertTrue(item.isCompleted)

        if case .message = VidurActions.prepare(.completeAction(query: "zebra"), current: meeting,
                                                modelContext: context, isRecording: false) {
            // An unknown action gets an honest message instead of a fake success.
        } else {
            XCTFail("Expected a message for an unknown action")
        }
    }

    func testCannotStartASecondRecording() throws {
        let context = try makeContext()
        if case .message = VidurActions.prepare(.startRecording, current: nil, modelContext: context, isRecording: true) {
            XCTAssertEqual(try context.fetch(FetchDescriptor<Meeting>()).count, 0)
        } else {
            XCTFail("Expected a message while recording")
        }
    }

    func testAssistantContextCountsOverdueActionsAndTodaysMeetings() throws {
        let context = try makeContext()
        let now = Date()
        let finished = Meeting(title: "Launch planning", createdAt: now.addingTimeInterval(-3 * 86_400),
                               scheduledStartTime: now.addingTimeInterval(-3 * 86_400), status: .completed)
        context.insert(finished)
        let late = ActionItem(title: "Late task", dueDate: now.addingTimeInterval(-86_400))
        context.insert(late)
        finished.addActionItem(late)
        let soon = now.addingTimeInterval(600)
        let upcoming = Meeting(title: "Design review", createdAt: now, scheduledStartTime: soon, status: .scheduled)
        context.insert(upcoming)
        try context.save()

        let snapshot = VidurActions.assistantContext(modelContext: context, userName: nil, selfNames: ["Me"],
                                                     isRecording: false, now: now)
        XCTAssertEqual(snapshot.overdueActionCount, 1)
        XCTAssertEqual(snapshot.nextMeeting?.title, "Design review")
        XCTAssertEqual(snapshot.lastMeetingTitle, "Launch planning")
        XCTAssertTrue(snapshot.hasAnyMeetings)
        XCTAssertFalse(snapshot.isRecording)
    }
}
