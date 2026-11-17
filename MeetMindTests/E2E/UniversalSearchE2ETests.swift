import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class UniversalSearchE2ETests: XCTestCase {
    func testSearchFindsSavedTranscriptAndItsMeeting() throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Planning")
        store.mainContext.insert(meeting)
        meeting.addTranscriptSegment(TranscriptSegment(text: "Migrate the database", startTime: 30, endTime: 35))
        try store.mainContext.save()
        let search = SearchViewModel(modelContext: store.mainContext)
        search.search(query: "database")
        let result = try XCTUnwrap(search.searchResults.first)
        XCTAssertEqual(result.category, .transcript)
        XCTAssertEqual(result.meetingId, meeting.id)
        XCTAssertEqual(result.timecode, 30)
        XCTAssertEqual(search.destination(for: result), .meetingDetail(id: meeting.id))
    }
    func testSearchDoesNotInventResultsForMissingWords() {
        let search = SearchViewModel()
        search.indexMeetings([Meeting(title: "Planning")])
        search.search(query: "unmentionedword")
        XCTAssertTrue(search.searchResults.isEmpty)
        XCTAssertTrue(search.hasEmptyResults)
    }
}
