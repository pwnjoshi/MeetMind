import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingCreationE2ETests: XCTestCase {
    func testSchedulePersistsMeetingIntoHomeFeed() throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let setup = MeetingSetupViewModel(modelContext: store.mainContext)
        setup.title = "Design review"
        setup.startDate = Date().addingTimeInterval(3600)
        setup.endDate = setup.startDate.addingTimeInterval(1800)
        let meeting = try setup.saveScheduledMeeting()
        let home = HomeViewModel(modelContext: store.mainContext)
        XCTAssertTrue(home.upcomingMeetings.contains { $0.id == meeting.id })
        XCTAssertEqual(meeting.duration, 1800)
    }
    func testInvalidDateRangeDoesNotPersistMeeting() throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let setup = MeetingSetupViewModel(modelContext: store.mainContext)
        setup.startDate = Date().addingTimeInterval(3600)
        setup.endDate = Date()
        XCTAssertThrowsError(try setup.saveScheduledMeeting())
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<Meeting>()), 0)
    }
}
