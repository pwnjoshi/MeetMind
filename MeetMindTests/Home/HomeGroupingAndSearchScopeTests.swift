import XCTest
import Foundation
import SwiftData
@testable import MeetMind

/// Home grouping (Upcoming / Recent) and Search scopes (All / Meetings / Transcripts / Actions).
@MainActor
final class HomeGroupingAndSearchScopeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Home grouping

    func test_home_groupsScheduledFutureAsUpcomingAndOthersAsRecent() throws {
        let future = Date().addingTimeInterval(86_400 * 3)
        let upcoming = Meeting(title: "Launch readiness", scheduledStartTime: future, status: .scheduled)
        let past = Meeting(title: "Finance review", createdAt: Date().addingTimeInterval(-86_400), status: .completed)
        context.insert(upcoming)
        context.insert(past)
        try context.save()

        let viewModel = HomeViewModel(modelContext: context)
        viewModel.fetchMeetings()

        XCTAssertEqual(viewModel.filteredUpcomingMeetings.map(\.title), ["Launch readiness"])
        XCTAssertEqual(viewModel.filteredRecentMeetings.map(\.title), ["Finance review"])
        XCTAssertFalse(viewModel.isEmptyState)
    }

    func test_home_emptyStoreIsEmptyState() {
        let viewModel = HomeViewModel(modelContext: context)
        viewModel.fetchMeetings()
        XCTAssertTrue(viewModel.isEmptyState)
    }

    // MARK: - Search scopes

    private func makeSearchViewModel() throws -> SearchViewModel {
        let meeting = Meeting(title: "Finance review", status: .completed)
        context.insert(meeting)
        let segment = TranscriptSegment(
            text: "Finance signs off on the estimate.", startTime: 190, endTime: 195, meeting: meeting
        )
        context.insert(segment)
        meeting.transcriptSegments = [segment]
        let action = ActionItem(title: "Share launch budget with Finance", meeting: meeting)
        context.insert(action)
        meeting.actionItems = [action]
        try context.save()

        let viewModel = SearchViewModel(modelContext: context)
        viewModel.indexMeetings([meeting])
        return viewModel
    }

    func test_search_allScopeReturnsEverySection() throws {
        let viewModel = try makeSearchViewModel()
        viewModel.setPresentedScope(.all)
        viewModel.search(query: "finance", recordsHistory: false)

        XCTAssertEqual(viewModel.meetingHits.count, 1)
        XCTAssertEqual(viewModel.transcriptResults.count, 1)
        XCTAssertEqual(viewModel.actionResults.count, 1)
    }

    func test_search_meetingsScopeExcludesTranscriptsAndActions() throws {
        let viewModel = try makeSearchViewModel()
        viewModel.setPresentedScope(.meetings)
        viewModel.search(query: "finance", recordsHistory: false)

        XCTAssertEqual(viewModel.meetingHits.count, 1)
        XCTAssertTrue(viewModel.transcriptResults.isEmpty)
        XCTAssertTrue(viewModel.actionResults.isEmpty)
    }

    func test_search_transcriptsScopeOnlyReturnsTranscripts() throws {
        let viewModel = try makeSearchViewModel()
        viewModel.setPresentedScope(.transcripts)
        viewModel.search(query: "finance", recordsHistory: false)

        XCTAssertTrue(viewModel.meetingHits.isEmpty)
        XCTAssertEqual(viewModel.transcriptResults.count, 1)
        XCTAssertTrue(viewModel.actionResults.isEmpty)
    }

    func test_search_actionsScopeOnlyReturnsActions() throws {
        let viewModel = try makeSearchViewModel()
        viewModel.setPresentedScope(.actions)
        viewModel.search(query: "finance", recordsHistory: false)

        XCTAssertTrue(viewModel.meetingHits.isEmpty)
        XCTAssertTrue(viewModel.transcriptResults.isEmpty)
        XCTAssertEqual(viewModel.actionResults.count, 1)
        XCTAssertNotNil(viewModel.actionResults.first?.detail)
    }

    func test_search_noMatchesIsEmpty() throws {
        let viewModel = try makeSearchViewModel()
        viewModel.search(query: "roadmap", recordsHistory: false)
        XCTAssertTrue(viewModel.hasEmptyResults)
    }
}
