import AVFoundation
import Foundation
import SwiftData
import XCTest
@testable import MeetMind

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    private var root: URL!
    private var documents: URL!
    private var recovery: URL!
    private var store: RecordingTakeJournalStore!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        documents = root.appendingPathComponent("Documents", isDirectory: true)
        recovery = root.appendingPathComponent("ApplicationSupport/Manent/RecordingRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        store = RecordingTakeJournalStore(documentsRoot: documents, recoveryRoot: recovery)
        container = try ModelContainerFactory.createInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        store = nil
        try? FileManager.default.removeItem(at: root)
        recovery = nil
        documents = nil
        root = nil
        try super.tearDownWithError()
    }

    func testAtomicJournalRoundTripAndStateTransitions() throws {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let clockedStore = RecordingTakeJournalStore(
            documentsRoot: documents,
            recoveryRoot: recovery,
            now: { clock }
        )
        let meetingID = UUID()
        let audioURL = documents.appendingPathComponent("Recordings/take.m4a")

        let starting = try clockedStore.createBeforeRecording(meetingID: meetingID, audioURL: audioURL)
        XCTAssertEqual(starting.state, .starting)
        XCTAssertEqual(starting.relativeAudioPath, "Recordings/take.m4a")
        XCTAssertFalse(starting.relativeAudioPath.contains(root.path))

        clock.addTimeInterval(1)
        _ = try clockedStore.transition(meetingID: meetingID, to: .recording)
        XCTAssertFalse(try clockedStore.updateDurationIfNeeded(meetingID: meetingID, duration: 4.9))
        clock.addTimeInterval(5)
        XCTAssertTrue(try clockedStore.updateDurationIfNeeded(meetingID: meetingID, duration: 5.1))
        _ = try clockedStore.transition(meetingID: meetingID, to: .stopping, duration: 6)
        _ = try clockedStore.transition(meetingID: meetingID, to: .validated, duration: 5.75)
        _ = try clockedStore.transition(meetingID: meetingID, to: .persisted, duration: 5.75)

        let decoded = try XCTUnwrap(clockedStore.load(meetingID: meetingID))
        XCTAssertEqual(decoded.state, .persisted)
        XCTAssertEqual(decoded.lastKnownDuration, 5.75)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(RecordingTakeJournal.self,
                                           from: Data(contentsOf: clockedStore.journalURL(for: meetingID))),
                       decoded)
    }

    func testRelativePathRebasesAfterContainerPathChanges() throws {
        let oldDocuments = root.appendingPathComponent("old-container/Documents", isDirectory: true)
        let newDocuments = root.appendingPathComponent("new-container/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDocuments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDocuments, withIntermediateDirectories: true)
        let oldStore = RecordingTakeJournalStore(documentsRoot: oldDocuments, recoveryRoot: recovery)
        let meetingID = UUID()
        _ = try oldStore.createBeforeRecording(
            meetingID: meetingID,
            audioURL: oldDocuments.appendingPathComponent("Recordings/rebased.m4a")
        )

        let newStore = RecordingTakeJournalStore(documentsRoot: newDocuments, recoveryRoot: recovery)
        let journal = try XCTUnwrap(newStore.load(meetingID: meetingID))

        XCTAssertEqual(try newStore.audioURL(for: journal),
                       newDocuments.appendingPathComponent("Recordings/rebased.m4a"))
    }

    func testOverwriteGuardPreservesValidTakeAndQuarantinesInvalidTake() throws {
        let validID = UUID()
        let validURL = documents.appendingPathComponent("Recordings/valid.caf")
        try writeAudio(to: validURL, frameCount: 8_000)

        XCTAssertThrowsError(try store.assertDestinationAvailable(meetingID: validID, audioURL: validURL)) { error in
            XCTAssertEqual(error as? RecordingRecoveryError, .recoveryRequired)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: validURL.path))
        XCTAssertEqual(try store.load(meetingID: validID)?.state, .validated)

        let invalidID = UUID()
        let invalidURL = documents.appendingPathComponent("Recordings/invalid.caf")
        try writeAudio(to: invalidURL, frameCount: 0)

        XCTAssertThrowsError(try store.assertDestinationAvailable(meetingID: invalidID, audioURL: invalidURL)) { error in
            XCTAssertEqual(error as? RecordingRecoveryError, .recoveryRequired)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
        let invalidJournal = try XCTUnwrap(store.load(meetingID: invalidID))
        XCTAssertTrue(invalidJournal.relativeAudioPath.hasPrefix("Recordings/Quarantine/"))
        XCTAssertNotNil(invalidJournal.failureCode)
        let quarantinedURL = try store.audioURL(for: invalidJournal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedURL.path))
    }

    func testProcessKillSimulationAttachesValidOrphanAndClearsJournal() throws {
        let meeting = Meeting(title: "Interrupted", status: .recording)
        container.mainContext.insert(meeting)
        try container.mainContext.save()
        let audioURL = documents.appendingPathComponent("Recordings/orphan.caf")
        try writeAudio(to: audioURL, frameCount: 12_000)
        _ = try store.createBeforeRecording(meetingID: meeting.id, audioURL: audioURL)
        _ = try store.transition(meetingID: meeting.id, to: .recording, duration: 99)

        let report = try coordinator().recoverInterruptedRecordings()

        XCTAssertEqual(report.recovered.map(\.meetingID), [meeting.id])
        XCTAssertTrue(report.pending.isEmpty)
        XCTAssertEqual(meeting.audioFileURL, audioURL)
        XCTAssertEqual(meeting.duration, 1.5, accuracy: 0.001)
        XCTAssertEqual(meeting.status, .processing)
        XCTAssertEqual(meeting.analysisState, "ready")
        XCTAssertNil(try store.load(meetingID: meeting.id))
    }

    func testAlreadyOwnedTakeOnlyClearsJournal() throws {
        let meeting = Meeting(title: "Already saved", status: .processing)
        let audioURL = documents.appendingPathComponent("Recordings/owned.caf")
        try writeAudio(to: audioURL, frameCount: 8_000)
        meeting.setAudioFileURL(audioURL)
        meeting.duration = 1
        container.mainContext.insert(meeting)
        try container.mainContext.save()
        _ = try store.createBeforeRecording(meetingID: meeting.id, audioURL: audioURL)
        _ = try store.transition(meetingID: meeting.id, to: .recording)

        let report = try coordinator().recoverInterruptedRecordings()

        XCTAssertTrue(report.recovered.isEmpty)
        XCTAssertTrue(report.pending.isEmpty)
        XCTAssertNil(try store.load(meetingID: meeting.id))
        XCTAssertEqual(meeting.audioFileURL, audioURL)
    }

    func testMissingMeetingStaysPendingUntilRecoveredAsNew() throws {
        let meetingID = UUID()
        let audioURL = documents.appendingPathComponent("Recordings/missing-meeting.caf")
        try writeAudio(to: audioURL, frameCount: 8_000)
        _ = try store.createBeforeRecording(meetingID: meetingID, audioURL: audioURL)
        _ = try store.transition(meetingID: meetingID, to: .recording)

        let first = try coordinator().recoverInterruptedRecordings()
        let pending = try XCTUnwrap(first.pending.first)
        XCTAssertEqual(pending.reason, .meetingMissing)
        XCTAssertNotNil(try store.load(meetingID: meetingID))

        let notice = try coordinator().recoverAsNewMeeting(pending)
        XCTAssertEqual(notice.meetingID, meetingID)
        XCTAssertNil(try store.load(meetingID: meetingID))
        let meetings = try container.mainContext.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(meetings.first?.title, "Recovered recording")
        XCTAssertEqual(meetings.first?.audioFileURL, audioURL)
    }

    func testInvalidFileIsQuarantinedAndRemainsPending() throws {
        let meeting = Meeting(title: "Invalid", status: .recording)
        container.mainContext.insert(meeting)
        try container.mainContext.save()
        let audioURL = documents.appendingPathComponent("Recordings/invalid-orphan.caf")
        try writeAudio(to: audioURL, frameCount: 0)
        _ = try store.createBeforeRecording(meetingID: meeting.id, audioURL: audioURL)
        _ = try store.transition(meetingID: meeting.id, to: .recording)

        let report = try coordinator().recoverInterruptedRecordings()
        let pending = try XCTUnwrap(report.pending.first)

        XCTAssertEqual(pending.reason, .invalidAudio)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        let quarantinedURL = try store.audioURL(for: pending.journal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedURL.path))
        XCTAssertNil(meeting.audioFileURL)
    }

    func testConfirmedPendingDeletionRemovesAudioAndJournal() throws {
        let meetingID = UUID()
        let audioURL = documents.appendingPathComponent("Recordings/delete.caf")
        try writeAudio(to: audioURL, frameCount: 8_000)
        let journal = try store.createBeforeRecording(meetingID: meetingID, audioURL: audioURL)
        let pending = PendingRecordingRecovery(journal: journal, reason: .meetingMissing)

        try coordinator().deletePendingRecovery(pending)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertNil(try store.load(meetingID: meetingID))
    }

    private func coordinator() -> RecordingRecoveryCoordinator {
        RecordingRecoveryCoordinator(modelContext: container.mainContext, store: store)
    }

    private func writeAudio(to url: URL, frameCount: AVAudioFrameCount) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frameCount)) else {
            throw AudioRecordingError.fileCreationFailed("Test audio format unavailable")
        }
        buffer.frameLength = frameCount
        if frameCount > 0 {
            buffer.floatChannelData?.pointee.initialize(repeating: 0, count: Int(frameCount))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        if frameCount > 0 { try file.write(from: buffer) }
    }
}
