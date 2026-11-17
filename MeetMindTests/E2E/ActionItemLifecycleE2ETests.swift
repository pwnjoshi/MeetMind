import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ActionItemLifecycleE2ETests: XCTestCase {
    func testSavedActionCompletionAppearsInActionHub() throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Decisions")
        store.mainContext.insert(meeting)
        let action = ActionItem(title: "Ship the repair", priority: .high)
        meeting.addActionItem(action)
        try store.mainContext.save()
        let hub = ActionItemsViewModel(modelContext: store.mainContext)
        XCTAssertEqual(hub.allActionItems.map(\.id), [action.id])
        hub.toggleCompletion(for: action)
        XCTAssertTrue(action.isCompleted)
        hub.fetchActionItems()
        XCTAssertTrue(try XCTUnwrap(hub.allActionItems.first).isCompleted)
    }
    func testDeletingMeetingCascadesActionItems() throws {
        let store = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Remove")
        store.mainContext.insert(meeting)
        meeting.addActionItem(ActionItem(title: "Remove with parent"))
        try store.mainContext.save()
        store.mainContext.delete(meeting)
        try store.mainContext.save()
        XCTAssertEqual(try store.mainContext.fetchCount(FetchDescriptor<ActionItem>()), 0)
    }
}
