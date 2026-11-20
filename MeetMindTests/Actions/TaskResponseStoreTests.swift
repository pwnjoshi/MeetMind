import XCTest
import Foundation
@testable import MeetMind

@MainActor
final class TaskResponseStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskResponseStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    func testRecordsAndReadsResponseByActionID() throws {
        let store = TaskResponseStore(fileURL: nil)
        let id = UUID()
        XCTAssertNil(store.response(for: id))
        try store.record(TaskResponse(kind: .confirmed), for: id)
        XCTAssertEqual(store.response(for: id)?.kind, .confirmed)
        XCTAssertEqual(store.response(for: id)?.summary, "Confirmed by owner")
    }

    func testCorrectionSummaryIncludesText() {
        let response = TaskResponse(kind: .correctionRequested, correctionText: "Move the deadline to Monday.")
        XCTAssertEqual(response.summary, "Correction requested: Move the deadline to Monday.")
        XCTAssertTrue(response.shareText(taskTitle: "Estimate", ownerName: "Vaishnavi").contains("Task for Vaishnavi: Estimate"))
    }

    func testResponsesPersistAcrossInstances() throws {
        let url = directory.appendingPathComponent("TaskResponses.json")
        let id = UUID()
        let first = TaskResponseStore(fileURL: url)
        try first.record(TaskResponse(kind: .correctionRequested, correctionText: "Later"), for: id)

        let second = TaskResponseStore(fileURL: url)
        XCTAssertEqual(second.response(for: id)?.kind, .correctionRequested)
        XCTAssertEqual(second.response(for: id)?.correctionText, "Later")
    }

    func testRemoveDeletesResponseOnDisk() throws {
        let url = directory.appendingPathComponent("TaskResponses.json")
        let id = UUID()
        let store = TaskResponseStore(fileURL: url)
        try store.record(TaskResponse(kind: .confirmed), for: id)
        store.remove(for: id)
        XCTAssertNil(store.response(for: id))
        XCTAssertNil(TaskResponseStore(fileURL: url).response(for: id))
    }

    func testNewResponseReplacesOldOne() throws {
        let store = TaskResponseStore(fileURL: nil)
        let id = UUID()
        try store.record(TaskResponse(kind: .correctionRequested, correctionText: "Fix"), for: id)
        try store.record(TaskResponse(kind: .confirmed), for: id)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.response(for: id)?.kind, .confirmed)
    }
}
