import XCTest
import Foundation
@testable import MeetMind

@MainActor
final class LocalInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testEmptyInputProducesNoItems() {
        XCTAssertTrue(LocalInboxBuilder.items(meetings: [], tasks: [], now: now).isEmpty)
    }

    func testMeetingStatesProduceMinutesAndFailureItems() {
        let ready = LocalInboxMeetingInput(id: UUID(), title: "Planning", date: now - day, analysisState: "completed", hasMinutes: true)
        let noMinutes = LocalInboxMeetingInput(id: UUID(), title: "Empty", date: now - day, analysisState: "completed", hasMinutes: false)
        let failed = LocalInboxMeetingInput(id: UUID(), title: "Broken", date: now - 2 * day, analysisState: "failed", hasMinutes: false)
        let running = LocalInboxMeetingInput(id: UUID(), title: "Busy", date: now, analysisState: "transcription", hasMinutes: false)
        let items = LocalInboxBuilder.items(meetings: [ready, noMinutes, failed, running], tasks: [], now: now)
        XCTAssertEqual(items.map(\.kind), [.minutesReady, .processingFailed])
        XCTAssertEqual(items.first?.meetingID, ready.id)
    }

    func testTaskWindowsAndOrdering() {
        let meetingID = UUID()
        func task(_ due: TimeInterval?, done: Bool = false, completedAt: Date? = nil) -> LocalInboxTaskInput {
            LocalInboxTaskInput(id: UUID(), title: "T", meetingID: meetingID, meetingTitle: "M",
                                dueDate: due.map { now + $0 }, isCompleted: done, completedAt: completedAt)
        }
        let overdue = task(-day)
        let soon = task(day)
        let far = task(10 * day)
        let none = task(nil)
        let fresh = task(nil, done: true, completedAt: now - day)
        let stale = task(nil, done: true, completedAt: now - 30 * day)
        let orphan = LocalInboxTaskInput(id: UUID(), title: "O", meetingID: nil, meetingTitle: nil,
                                         dueDate: now + day, isCompleted: false, completedAt: nil)
        let items = LocalInboxBuilder.items(meetings: [], tasks: [overdue, soon, far, none, fresh, stale, orphan], now: now)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].kind, .taskDue)
        XCTAssertEqual(items[1].kind, .taskCompleted)
        XCTAssertEqual(items[2].kind, .taskOverdue)
    }

    func testDerivationIsDeterministic() {
        let meeting = LocalInboxMeetingInput(id: UUID(), title: "A", date: now, analysisState: "completed", hasMinutes: true)
        let first = LocalInboxBuilder.items(meetings: [meeting], tasks: [], now: now)
        let second = LocalInboxBuilder.items(meetings: [meeting], tasks: [], now: now)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.id, "minutes-\(meeting.id.uuidString)")
    }

    func testReadStorePersistsAndCounts() throws {
        let suite = "MeetMindInboxTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = LocalInboxMeetingInput(id: UUID(), title: "A", date: now, analysisState: "completed", hasMinutes: true)
        let failed = LocalInboxMeetingInput(id: UUID(), title: "B", date: now - day, analysisState: "failed", hasMinutes: false)
        let items = LocalInboxBuilder.items(meetings: [meeting, failed], tasks: [], now: now)
        let store = LocalInboxReadStore(defaults: defaults)
        XCTAssertEqual(store.unreadCount(in: items), 2)
        store.markRead(items[0].id)
        XCTAssertEqual(LocalInboxReadStore(defaults: defaults).unreadCount(in: items), 1)
        store.markAllRead(items)
        XCTAssertEqual(store.unreadCount(in: items), 0)
        store.reset()
        XCTAssertEqual(store.unreadCount(in: items), 2)
    }

    func testStorageTotalsAndOrdering() {
        let url = URL(fileURLWithPath: "/tmp/a.m4a")
        let older = LocalRecordingFile(id: UUID(), title: "Old", date: now - day, duration: 60, bytes: 1_000, url: url)
        let newer = LocalRecordingFile(id: UUID(), title: "New", date: now, duration: 90, bytes: 2_500, url: url)
        XCTAssertEqual(LocalRecordingStorage.totalBytes([older, newer]), 3_500)
        XCTAssertEqual(LocalRecordingStorage.totalBytes([]), 0)
        XCTAssertEqual(LocalRecordingStorage.newestFirst([older, newer]).map(\.title), ["New", "Old"])
        XCTAssertEqual(LocalRecordingStorage.formatted(duration: 948), "15:48")
        XCTAssertEqual(LocalRecordingStorage.formatted(duration: 3_725), "1:02:05")
    }

    func testRemoveAudioFilesDeletesOnlyAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStorageTests-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("one.m4a")
        let nestedAudio = nested.appendingPathComponent("two.WAV")
        let other = root.appendingPathComponent("keep.json")
        try Data(count: 100).write(to: audio)
        try Data(count: 50).write(to: nestedAudio)
        try Data(count: 10).write(to: other)
        XCTAssertEqual(LocalRecordingStorage.fileSize(at: audio), 100)
        let removed = LocalRecordingStorage.removeAudioFiles(under: root)
        XCTAssertEqual(removed.files, 2)
        XCTAssertEqual(removed.bytes, 150)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedAudio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}
