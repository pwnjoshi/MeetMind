import XCTest
import Foundation
import SwiftData
import MessageUI
@testable import MeetMind

@MainActor
final class MoMTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MoM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    private var sidecarURL: URL { root.appendingPathComponent("Manent/MinutesOfMeeting.json") }

    // MARK: Reference number

    func testReferenceInitialsAndFormat() {
        XCTAssertEqual(MoMReference.initials(from: "Design review"), "DR")
        XCTAssertEqual(MoMReference.initials(from: "Standup"), "ST")
        XCTAssertEqual(MoMReference.initials(from: "  "), "MM")
        XCTAssertEqual(MoMReference.format(title: "Design review", year: 2026, sequence: 46), "MOM/DR/2026/046")
    }

    func testReferenceNumberIsStableAcrossCallsRenamesAndReload() throws {
        let store = MoMSidecarStore(fileURL: sidecarURL)
        let meetingID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.referenceNumber(for: meetingID, title: "Design review", date: date)
        let again = try store.referenceNumber(for: meetingID, title: "Renamed meeting", date: date)
        XCTAssertEqual(first, again)

        let other = try store.referenceNumber(for: UUID(), title: "Design review", date: date)
        XCTAssertNotEqual(first, other)

        let reloaded = MoMSidecarStore(fileURL: sidecarURL)
        XCTAssertEqual(try reloaded.referenceNumber(for: meetingID, title: "Anything", date: date), first)
    }

    // MARK: Sidecar persistence

    func testSidecarRoundTripRemoveAndEraseAll() throws {
        let store = MoMSidecarStore(fileURL: sidecarURL)
        let id = UUID()
        try store.update(id) {
            $0.venue = "Conf. Room 2"
            $0.signaturePNG = Data([1, 2, 3])
            $0.signedAt = Date(timeIntervalSince1970: 100)
            $0.topics = [MoMTopic(id: "t", title: "Launch date", outcomeKind: .deferred, outcomeText: "Wait")]
        }
        let reloaded = MoMSidecarStore(fileURL: sidecarURL)
        XCTAssertEqual(reloaded.sidecar(for: id).venue, "Conf. Room 2")
        XCTAssertTrue(reloaded.sidecar(for: id).isSigned)
        XCTAssertEqual(reloaded.sidecar(for: id).topics?.first?.outcomeKind, .deferred)

        try reloaded.remove(meetingID: id)
        XCTAssertEqual(reloaded.sidecar(for: id), MoMSidecar())

        try reloaded.update(id) { $0.venue = "x" }
        try reloaded.eraseAll()
        XCTAssertTrue(reloaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL.path))
    }

    func testSidecarDecodesOlderJSONWithMissingKeys() throws {
        let json = Data("{\"venue\":\"Hall\"}".utf8)
        let decoded = try JSONDecoder().decode(MoMSidecar.self, from: json)
        XCTAssertEqual(decoded.venue, "Hall")
        XCTAssertEqual(decoded.inviteeIDs, [])
        XCTAssertNil(decoded.topics)
    }

    func testCorruptSidecarIsReportedNotOverwritten() throws {
        try FileManager.default.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: sidecarURL)
        let store = MoMSidecarStore(fileURL: sidecarURL)
        XCTAssertThrowsError(try store.update(UUID()) { $0.venue = "x" })
        XCTAssertEqual(try Data(contentsOf: sidecarURL), Data("not json".utf8))
    }

    func testDeletionCoordinatorRemovesMoMSidecar() async throws {
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        for url in [documents, support, temporary] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let suite = "MoM.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let configuration = ModelConfiguration(schema: ModelContainerFactory.schema,
            url: support.appendingPathComponent("meetings.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        let meeting = Meeting(title: "Design review")
        container.mainContext.insert(meeting)
        try container.mainContext.save()

        let mom = MoMSidecarStore(fileURL: support.appendingPathComponent("Manent/MinutesOfMeeting.json"))
        try mom.update(meeting.id) { $0.venue = "Private venue" }

        let inventory = UserContentInventory(documentsRoot: documents, applicationSupportRoot: support, temporaryRoot: temporary)
        let coordinator = DeletionCoordinator(
            context: container.mainContext, inventory: inventory, defaults: defaults,
            meetingRecords: MeetingRecordStore(fileURL: support.appendingPathComponent("MeetingRecords.json")),
            taskResponses: TaskResponseStore(fileURL: support.appendingPathComponent("MeetMind/TaskResponses.json")),
            minutesStudio: MinutesStudioStore(directory: support.appendingPathComponent("MinutesStudio")),
            meetingPrep: MeetingPrepStore(defaults: defaults),
            approvals: MinutesApprovalStore(fileURL: support.appendingPathComponent("Manent/MinutesApprovals.json")),
            vidur: VidurPreferences(defaults: defaults),
            jobs: AnalysisJobStore(fileURL: support.appendingPathComponent("OfflineIntelligence/AnalysisJobs/jobs-v1.json")),
            momSidecars: mom, clearsSystemNotifications: false, clearsLiveAnalysisPipeline: false)

        _ = try await coordinator.deleteMeeting(meeting)
        XCTAssertEqual(mom.sidecar(for: meeting.id), MoMSidecar())
    }

    // MARK: Topic rendering and fallback

    func testTopicFallbackUsesDiscussionDecisionsAndOpenIssues() {
        let topics = MoMTopicResolver.resolve(edited: nil, engine: [], discussion: ["Reviewed readiness"],
                                              decisions: ["Launch on 18 Nov"], openIssues: ["Budget pending"])
        XCTAssertEqual(topics.count, 3)
        XCTAssertEqual(topics[0].discussion, ["Reviewed readiness"])
        XCTAssertFalse(topics[0].hasOutcome)
        XCTAssertEqual(topics[1].outcomeKind, .resolved)
        XCTAssertEqual(topics[2].outcomeKind, .open)
        XCTAssertTrue(MoMTopicResolver.resolve(edited: nil, engine: [], discussion: [], decisions: [], openIssues: []).isEmpty)
    }

    func testEditedTopicsWinOverEngineTopicsWhichWinOverFallback() {
        let engine = [MoMTopic(id: "e", title: "Engine")]
        let edited = [MoMTopic(id: "u", title: "User")]
        XCTAssertEqual(MoMTopicResolver.resolve(edited: edited, engine: engine, discussion: ["x"], decisions: [], openIssues: []).first?.title, "User")
        XCTAssertEqual(MoMTopicResolver.resolve(edited: nil, engine: engine, discussion: ["x"], decisions: [], openIssues: []).first?.title, "Engine")
    }

    func testEngineFieldsParseDefensively() {
        XCTAssertEqual(MoMEngineFields.parse(nil), .empty)
        XCTAssertEqual(MoMEngineFields.parse(Data("[1,2]".utf8)), .empty)
        XCTAssertEqual(MoMEngineFields.parse(Data("{\"topics\":\"oops\",\"suggestedAttendees\":7}".utf8)), .empty)

        let json = """
        {"analysis":[{"topics":[
          {"title":"Launch date","discussion":["a","b"],
           "outcome":{"kind":"deferred","text":"Wait for QA"},"timestamp":"12:10","speaker":"Maya Rao"},
          {"title":"  "},
          {"title":"Checklist","outcome":"Pawan owns it","timestamp":1265}],
         "suggestedAttendees":[{"name":"Garima Pant","evidence":"mentioned"},"Garima Pant"],
         "nextMeeting":{"date":"2026-11-19T09:00:00Z","text":"Same venue"}}]}
        """
        let parsed = MoMEngineFields.parse(Data(json.utf8))
        XCTAssertEqual(parsed.topics.count, 2)
        XCTAssertEqual(parsed.topics[0].outcomeKind, .deferred)
        XCTAssertEqual(parsed.topics[0].timestamp, 730)
        XCTAssertEqual(parsed.topics[0].sourceChipText, "Maya \u{00B7} 12:10")
        XCTAssertEqual(parsed.topics[1].outcomeText, "Pawan owns it")
        XCTAssertEqual(parsed.suggestedAttendees.map(\.name), ["Garima Pant"])
        XCTAssertNotNil(parsed.nextMeeting?.date)
        XCTAssertEqual(parsed.nextMeeting?.note, "Same venue")
    }

    func testGenericSpeakerLabelsNeverAppearInSourceChip() {
        let topic = MoMTopic(id: "t", title: "T", outcomeText: "x", speaker: "Speaker 1", timestamp: 65)
        XCTAssertEqual(topic.sourceChipText, "1:05")
        XCTAssertTrue(MoMTopic.isGenericSpeakerLabel("S2"))
        XCTAssertFalse(MoMTopic.isGenericSpeakerLabel("Sachin"))
    }

    // MARK: Share outcome routing

    func testEveryCompletedShareReachesSentScreen() {
        XCTAssertTrue(MoMShareRouting.showsSentScreen(.mailSent))
        XCTAssertTrue(MoMShareRouting.showsSentScreen(.shared))
        XCTAssertFalse(MoMShareRouting.showsSentScreen(.cancelled))
        XCTAssertFalse(MoMShareRouting.showsSentScreen(.mailSaved))
        XCTAssertFalse(MoMShareRouting.showsSentScreen(.failed("x")))
        XCTAssertEqual(MinutesShareOutcome.fromActivity(completed: true), .shared)
        XCTAssertEqual(MinutesShareOutcome.fromActivity(completed: false), .cancelled)
        XCTAssertEqual(MinutesShareOutcome.fromMail(.sent, error: nil), .mailSent)
    }

    func testShareSheetCopyDoesNotClaimDelivery() throws {
        let shared = try XCTUnwrap(MinutesSentState.make(outcome: .shared, recipients: []))
        XCTAssertEqual(shared.title, "Minutes Shared")
        XCTAssertFalse(shared.title.contains("Sent"))
        let mail = try XCTUnwrap(MinutesSentState.make(outcome: .mailSent, recipients: []))
        XCTAssertEqual(mail.title, "Minutes Sent")
        XCTAssertTrue(mail.message.contains("cannot see whether they arrived"))
    }
}
