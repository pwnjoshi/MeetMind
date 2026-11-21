import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Recent on Home: every meeting that is not an upcoming plan appears, newest first,
/// including recordings that are still in progress, with a clear status line.
@MainActor
final class HomeRecentMeetingsTests: XCTestCase {
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

    private func completed(_ title: String, daysAgo: Double) -> Meeting {
        let created = Date().addingTimeInterval(-86_400 * daysAgo)
        let meeting = Meeting(title: title, createdAt: created, duration: 600, status: .completed)
        context.insert(meeting)
        return meeting
    }

    // MARK: Ordering and membership

    func test_recent_includesInProgressMeetingsNewestFirst() throws {
        _ = completed("Old sync", daysAgo: 2)
        let processing = Meeting(title: "Quick meeting", createdAt: Date().addingTimeInterval(-1_800),
                                 duration: 300, status: .processing)
        context.insert(processing)
        let recording = Meeting(title: "Live now", createdAt: Date().addingTimeInterval(-120), status: .recording)
        context.insert(recording)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)
        viewModel.fetchMeetings()

        XCTAssertEqual(viewModel.recentMeetings.map(\.title), ["Live now", "Quick meeting", "Old sync"])
        XCTAssertTrue(viewModel.upcomingMeetings.isEmpty)
    }

    /// Reproduces "the last meeting I recorded is not in Recent". A scheduled meeting that is recorded
    /// later kept its old planned time as sort key, so four newer rows pushed it out of the Recent card.
    func test_recent_recordedScheduledMeetingSortsByWhenItWasRecorded() throws {
        let audio = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).m4a")
        try Data([0, 1, 2]).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }

        for index in 1...5 { _ = completed("Meeting \(index)", daysAgo: Double(index)) }
        let planned = Date().addingTimeInterval(-86_400 * 9)
        let scheduled = Meeting(title: "Planned review", createdAt: planned.addingTimeInterval(-86_400),
                                scheduledStartTime: planned, duration: 900, status: .processing,
                                audioFileURL: audio)
        context.insert(scheduled)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)
        viewModel.fetchMeetings()

        XCTAssertEqual(viewModel.recentMeetings.first?.id, scheduled.id)
        XCTAssertTrue(viewModel.recentMeetings.prefix(4).contains { $0.id == scheduled.id })
    }

    func test_recent_scheduledMeetingStartedEarlyIsNotSortedByItsFutureTime() throws {
        let startedEarly = Meeting(title: "Started early", createdAt: Date().addingTimeInterval(-7_200),
                                   scheduledStartTime: Date().addingTimeInterval(86_400 * 3),
                                   duration: 600, status: .processing)
        context.insert(startedEarly)
        try context.save()

        let now = Date()
        let date = HomeViewModel.recencyDate(for: startedEarly, now: now)
        XCTAssertLessThanOrEqual(date, now)
        XCTAssertGreaterThan(date, startedEarly.createdAt)
    }

    /// A discarded recording stayed in the view model's in-memory list and kept showing in Recent.
    func test_recent_discardedQuickMeetingDisappears() throws {
        let viewModel = HomeViewModel(modelContext: context)
        let quick = Meeting(title: "Quick meeting", createdAt: Date(), duration: 0, status: .recording)
        viewModel.addMeeting(quick)
        XCTAssertEqual(viewModel.recentMeetings.map(\.title), ["Quick meeting"])

        context.delete(quick)
        try context.save()
        viewModel.fetchMeetings()

        XCTAssertTrue(viewModel.recentMeetings.isEmpty)
        XCTAssertTrue(viewModel.isEmptyState)
    }

    func test_recent_scheduledFutureMeetingStaysUpcomingOnly() throws {
        let future = Meeting(title: "Planning", scheduledStartTime: Date().addingTimeInterval(7_200), status: .scheduled)
        context.insert(future)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)
        viewModel.fetchMeetings()

        XCTAssertEqual(viewModel.upcomingMeetings.map(\.title), ["Planning"])
        XCTAssertTrue(viewModel.recentMeetings.isEmpty)
    }

    // MARK: Status line

    func test_line_recordingAndProcessing() {
        let recording = Meeting(title: "A", status: .recording)
        XCTAssertEqual(RecentMeetingPresenter.line(for: recording, reviewStatus: nil),
                       RecentMeetingLine(text: "Recording\u{2026}", tone: .active))

        let processing = Meeting(title: "B", duration: 720, status: .processing)
        XCTAssertEqual(RecentMeetingPresenter.line(for: processing, reviewStatus: nil).text,
                       "Processing\u{2026} \u{00B7} 12 min")

        processing.analysisState = "speakerReview"
        let review = RecentMeetingPresenter.line(for: processing, reviewStatus: nil)
        XCTAssertEqual(review.text, "Needs speaker review \u{00B7} 12 min")
        XCTAssertEqual(review.tone, .attention)

        processing.analysisState = "failed"
        XCTAssertEqual(RecentMeetingPresenter.line(for: processing, reviewStatus: nil).tone, .failure)
    }

    func test_line_completedMeetings() {
        let draft = Meeting(title: "Draft", duration: 3_600, status: .completed)
        draft.minutesNeedFinalization = true
        XCTAssertEqual(RecentMeetingPresenter.line(for: draft, reviewStatus: nil).text, "Draft minutes \u{00B7} 1h")

        let finalized = Meeting(title: "Final", status: .completed)
        XCTAssertEqual(RecentMeetingPresenter.line(for: finalized, reviewStatus: "Finalized").text, "Finalized")

        let withActions = Meeting(title: "Actions", duration: 600, status: .completed)
        context.insert(withActions)
        for title in ["One", "Two"] {
            let item = ActionItem(title: title)
            context.insert(item)
            withActions.addActionItem(item)
        }
        XCTAssertEqual(RecentMeetingPresenter.line(for: withActions, reviewStatus: "Finalized").text,
                       "2 open actions \u{00B7} 10 min")
        XCTAssertEqual(RecentMeetingPresenter.line(for: withActions, reviewStatus: "Draft").text,
                       "Draft minutes \u{00B7} 2 open actions \u{00B7} 10 min")
    }

    func test_title_fallsBackWhenEmpty() {
        XCTAssertEqual(RecentMeetingPresenter.title(for: Meeting(title: "  ")), "Untitled meeting")
        XCTAssertEqual(RecentMeetingPresenter.title(for: Meeting(title: " Standup ")), "Standup")
    }

    func test_durationText() {
        XCTAssertNil(RecentMeetingPresenter.durationText(0))
        XCTAssertEqual(RecentMeetingPresenter.durationText(20), "1 min")
        XCTAssertEqual(RecentMeetingPresenter.durationText(3_900), "1h 5m")
    }
}
