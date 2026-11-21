import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Quick Meet goes straight to the recorder: the meeting is created as `.recording`,
/// shows up in Recent at once and keeps showing through processing and completion.
@MainActor
final class QuickMeetingRecentTests: XCTestCase {
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

    func test_quickMeeting_appearsAtOnceAndTracksStatusTransitions() throws {
        let viewModel = HomeViewModel(modelContext: context)
        let older = Meeting(title: "Yesterday sync", createdAt: Date().addingTimeInterval(-86_400),
                            duration: 900, status: .completed)
        context.insert(older)
        try context.save()

        let quick = Meeting(title: "Quick meeting", createdAt: Date(), duration: 0, status: .recording)
        viewModel.addMeeting(quick)
        XCTAssertEqual(viewModel.recentMeetings.map(\.title), ["Quick meeting", "Yesterday sync"])
        XCTAssertEqual(RecentMeetingPresenter.line(for: quick, reviewStatus: nil).text, "Recording\u{2026}")

        quick.duration = 600
        viewModel.transitionStatus(for: quick, to: .processing)
        XCTAssertEqual(viewModel.recentMeetings.first?.id, quick.id)
        XCTAssertEqual(RecentMeetingPresenter.line(for: quick, reviewStatus: nil).text,
                       "Processing\u{2026} \u{00B7} 10 min")

        viewModel.transitionStatus(for: quick, to: .completed)
        XCTAssertEqual(viewModel.recentMeetings.first?.id, quick.id)
        XCTAssertEqual(viewModel.recentMeetings.count, 2)
    }

    func test_quickMeeting_neverNeedsAnUpcomingSlot() throws {
        let viewModel = HomeViewModel(modelContext: context)
        viewModel.addMeeting(Meeting(title: "Quick meeting", createdAt: Date(), status: .recording))
        XCTAssertTrue(viewModel.upcomingMeetings.isEmpty)
        XCTAssertEqual(viewModel.filteredRecentMeetings.count, 1)
    }
}
