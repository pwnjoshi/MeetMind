import XCTest
import Foundation
import SwiftData
import PDFKit
@testable import MeetMind

@MainActor
final class DataLifecycleTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var configuration: ModelConfiguration!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StageB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "StageB.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        configuration = ModelConfiguration(schema: ModelContainerFactory.schema,
            url: root.appendingPathComponent("ApplicationSupport/meetings.store"), cloudKitDatabase: .none)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        root = nil
        defaults = nil
        configuration = nil
        try super.tearDownWithError()
    }

    func testEraseAllRemovesPrivateArtifactsAfterFreshContextAndPreservesModels() async throws {
        let fixture = try await makeFixture()
        let meeting = try populateEveryEntity(in: fixture.container.mainContext, roots: fixture.inventory)
        try await populateEverySidecar(fixture, meeting: meeting)
        try populateEveryFileType(fixture.inventory, meeting: meeting)

        let modelSentinel = fixture.inventory.modelsRoot.appendingPathComponent("public-model/verified.json")
        try write("model", to: modelSentinel)
        let voiceProfile = fixture.inventory.temporaryRoot.appendingPathComponent("voice_baseline_profile.m4a")
        try write("voice", to: voiceProfile)
        let profile = UserProfile(name: "Private user", email: "private@example.test", role: "Private",
                                  voiceProfileURL: voiceProfile)
        defaults.set(try JSONEncoder().encode(profile), forKey: "MeetMind_UserProfile")
        defaults.set("qwen-1.7b", forKey: "Manent.vidurModel")
        defaults.set("secret", forKey: "MeetMind_APIKey")
        defaults.set(true, forKey: "MeetMind_IsOnboardingCompleted")
        defaults.set([meeting.id.uuidString], forKey: "MeetMind.pendingOfflineAnalysisIDs")
        defaults.set(true, forKey: "manent.calendar.connected")

        let report = try await fixture.coordinator.eraseAll()
        XCTAssertEqual(report.meetingsDeleted, 1)
        XCTAssertFalse(report.resumed)

        let fresh = ModelContext(fixture.container)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Meeting>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<TranscriptSegment>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Summary>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<ActionItem>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Note>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Speaker>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Tag>()), 0)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<Folder>()), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelSentinel.path))
        XCTAssertEqual(defaults.string(forKey: "Manent.vidurModel"), "qwen-1.7b")
        XCTAssertNil(defaults.object(forKey: "MeetMind_APIKey"))
        XCTAssertNil(defaults.object(forKey: "MeetMind_IsOnboardingCompleted"))
        XCTAssertTrue(fixture.records.isEmpty)
        XCTAssertTrue(fixture.responses.isEmpty)
        XCTAssertTrue(fixture.studio.isEmpty)
        XCTAssertTrue(fixture.prep.isEmpty)
        XCTAssertTrue(fixture.approvals.isEmpty)
        XCTAssertTrue(fixture.vidur.isEmpty)
        let jobsAreEmpty = try await fixture.jobs.isEmpty()
        XCTAssertTrue(jobsAreEmpty)
        for url in fixture.inventory.eraseAllDirectories + fixture.inventory.eraseAllFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Private artifact remains: \(url.path)")
        }
        let documentFiles = try FileManager.default.contentsOfDirectory(at: fixture.inventory.documentsRoot,
                                                                         includingPropertiesForKeys: nil)
        XCTAssertFalse(documentFiles.contains { LocalRecordingStorage.audioExtensions.contains($0.pathExtension.lowercased()) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: voiceProfile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inventory.journalURL.path))
    }

    func testInterruptedEraseResumesFromDurableJournal() async throws {
        let fixture = try await makeFixture(interruptAfterJournalWrite: true)
        let meeting = try populateEveryEntity(in: fixture.container.mainContext, roots: fixture.inventory)
        try populateEveryFileType(fixture.inventory, meeting: meeting)

        do {
            _ = try await fixture.coordinator.eraseAll()
            XCTFail("Expected the injected interruption")
        } catch let error as DeletionCoordinatorError {
            guard case .incomplete = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.inventory.journalURL.path))
        XCTAssertEqual(try fixture.container.mainContext.fetchCount(FetchDescriptor<Meeting>()), 1)

        let resumed = makeCoordinator(fixture: fixture, interruptAfterJournalWrite: false)
        let report = try await resumed.resumePendingDeletionIfNeeded()
        XCTAssertEqual(report?.resumed, true)
        XCTAssertEqual(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Meeting>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.inventory.journalURL.path))
    }

    func testMeetingDeletionRemovesOnlyOwnedMeetingArtifacts() async throws {
        let fixture = try await makeFixture()
        let context = fixture.container.mainContext
        let doomed = Meeting(title: "Delete")
        let kept = Meeting(title: "Keep")
        context.insert(doomed)
        context.insert(kept)
        let action = ActionItem(title: "Private task")
        let actionID = action.id
        doomed.addActionItem(action)
        let attachment = fixture.inventory.documentsRoot.appendingPathComponent("Attachments/doomed.jpg")
        doomed.addNote(Note(content: "photo", imageAttachmentPath: attachment.path))
        let audio = fixture.inventory.documentsRoot.appendingPathComponent("Recordings/doomed.m4a")
        doomed.setAudioFileURL(audio)
        try context.save()
        try write("audio", to: audio)
        try write("photo", to: attachment)
        try write("chunk", to: fixture.inventory.meetingDirectories(doomed.id)[0].appendingPathComponent("chunk.caf"))
        try write("checkpoint", to: fixture.inventory.meetingFiles(doomed.id)[0])
        let recoveryStore = RecordingTakeJournalStore(
            documentsRoot: fixture.inventory.documentsRoot,
            recoveryRoot: fixture.inventory.recordingRecoveryRoot
        )
        _ = try recoveryStore.createBeforeRecording(meetingID: doomed.id, audioURL: audio)
        try fixture.records.update(doomed.id) { $0.keptPrivate = true }
        try fixture.records.update(kept.id) { $0.keptPrivate = true }
        try fixture.responses.record(TaskResponse(kind: .confirmed), for: actionID)
        fixture.prep.update(doomed.id) { $0.calendarEventID = "event" }
        fixture.studio.save(.standard(), for: doomed.id)
        _ = try fixture.studio.saveCurrentSetup(named: "Global template", from: .standard())
        fixture.approvals.add(MinutesApprovalRecord(meetingID: doomed.id, reviewerName: "A", reviewerEmail: nil,
                                                    channel: .shareSheet, versionTag: "12345678"))
        fixture.vidur.record(VidurHistoryEntry(meetingID: doomed.id, question: "Q", answer: "A"))
        LocalInboxReadStore(defaults: defaults).markRead("minutes-\(doomed.id.uuidString)")
        _ = try await fixture.jobs.upsert(AnalysisJobRecord(meetingID: doomed.id, sourceFingerprint: "x",
            checkpointVersion: "1", requiredModels: []))

        _ = try await fixture.coordinator.deleteMeeting(doomed)

        XCTAssertNil(try context.fetch(FetchDescriptor<Meeting>()).first { $0.id == doomed.id })
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Meeting>()).first { $0.id == kept.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryStore.journalURL(for: doomed.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertNil(fixture.responses.response(for: actionID))
        XCTAssertEqual(fixture.records.record(for: doomed.id), MeetingRecordData())
        XCTAssertTrue(fixture.records.record(for: kept.id).keptPrivate)
        XCTAssertNil(fixture.prep.record(for: doomed.id).calendarEventID)
        XCTAssertNil(fixture.studio.config(for: doomed.id))
        XCTAssertEqual(fixture.studio.templates.count, 1, "Meeting deletion must preserve global templates")
        XCTAssertTrue(fixture.approvals.records(for: doomed.id).isEmpty)
        XCTAssertTrue(fixture.vidur.history(for: doomed.id).isEmpty)
        XCTAssertFalse(LocalInboxReadStore(defaults: defaults).readIDs.contains("minutes-\(doomed.id.uuidString)"))
        let deletedJob = try await fixture.jobs.get(doomed.id)
        XCTAssertNil(deletedJob)
    }

    private typealias Fixture = (container: ModelContainer, inventory: UserContentInventory,
        records: MeetingRecordStore, responses: TaskResponseStore, studio: MinutesStudioStore,
        prep: MeetingPrepStore, approvals: MinutesApprovalStore, vidur: VidurPreferences,
        jobs: AnalysisJobStore, coordinator: DeletionCoordinator)

    private func makeFixture(interruptAfterJournalWrite: Bool = false) async throws -> Fixture {
        let support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let container = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        let inventory = UserContentInventory(documentsRoot: documents, applicationSupportRoot: support,
                                             temporaryRoot: temporary)
        let records = MeetingRecordStore(fileURL: support.appendingPathComponent("MeetingRecords.json"))
        let responses = TaskResponseStore(fileURL: support.appendingPathComponent("MeetMind/TaskResponses.json"))
        let studio = MinutesStudioStore(directory: support.appendingPathComponent("MinutesStudio"))
        let prep = MeetingPrepStore(defaults: defaults)
        let approvals = MinutesApprovalStore(fileURL: support.appendingPathComponent("Manent/MinutesApprovals.json"))
        let vidur = VidurPreferences(defaults: defaults)
        let jobs = AnalysisJobStore(fileURL: support.appendingPathComponent("OfflineIntelligence/AnalysisJobs/jobs-v1.json"))
        let base = (container, inventory, records, responses, studio, prep, approvals, vidur, jobs)
        let coordinator = DeletionCoordinator(context: container.mainContext, inventory: inventory, defaults: defaults,
            meetingRecords: records, taskResponses: responses, minutesStudio: studio, meetingPrep: prep,
            approvals: approvals, vidur: vidur, jobs: jobs, clearsSystemNotifications: false,
            clearsLiveAnalysisPipeline: false, interruptAfterJournalWrite: interruptAfterJournalWrite)
        return (base.0, base.1, base.2, base.3, base.4, base.5, base.6, base.7, base.8, coordinator)
    }

    private func makeCoordinator(fixture: Fixture, interruptAfterJournalWrite: Bool) -> DeletionCoordinator {
        DeletionCoordinator(context: fixture.container.mainContext, inventory: fixture.inventory, defaults: defaults,
            meetingRecords: fixture.records, taskResponses: fixture.responses, minutesStudio: fixture.studio,
            meetingPrep: fixture.prep, approvals: fixture.approvals, vidur: fixture.vidur, jobs: fixture.jobs,
            clearsSystemNotifications: false, clearsLiveAnalysisPipeline: false,
            interruptAfterJournalWrite: interruptAfterJournalWrite)
    }

    private func populateEveryEntity(in context: ModelContext, roots: UserContentInventory) throws -> Meeting {
        let folder = Folder(name: "Private folder")
        let tag = Tag(name: "Private tag")
        let speakerVoice = roots.documentsRoot.appendingPathComponent("Recordings/speaker-voice.m4a")
        let speaker = Speaker(name: "Private speaker", voiceSampleURL: speakerVoice)
        let meeting = Meeting(title: "Private meeting")
        context.insert(folder)
        context.insert(tag)
        context.insert(speaker)
        context.insert(meeting)
        meeting.folder = folder
        meeting.tags = [tag]
        meeting.addParticipant(speaker)
        meeting.addTranscriptSegment(TranscriptSegment(text: "Private transcript", startTime: 0, endTime: 1))
        meeting.summary = Summary(executiveSummary: "Private minutes", keyPoints: ["point"], keyDecisions: ["decision"])
        meeting.addActionItem(ActionItem(title: "Private action", assignee: speaker))
        let attachment = roots.documentsRoot.appendingPathComponent("Attachments/private.jpg")
        meeting.addNote(Note(content: "Private note", imageAttachmentPath: attachment.path))
        let audio = roots.documentsRoot.appendingPathComponent("Recordings/private.m4a")
        meeting.setAudioFileURL(audio)
        try context.save()
        try write("audio", to: audio)
        try write("voice", to: speakerVoice)
        try write("photo", to: attachment)
        return meeting
    }

    private func populateEverySidecar(_ fixture: Fixture, meeting: Meeting) async throws {
        try fixture.records.update(meeting.id) { $0.keptPrivate = true }
        let actionID = try XCTUnwrap(meeting.actionItems.first?.id)
        try fixture.responses.record(TaskResponse(kind: .correctionRequested, correctionText: "Private"), for: actionID)
        fixture.prep.update(meeting.id) { $0.calendarEventID = "private-event" }
        fixture.studio.save(.standard(), for: meeting.id)
        _ = try fixture.studio.saveCurrentSetup(named: "Private template", from: .standard())
        let externalAssets = root.appendingPathComponent("ImportFixtures", isDirectory: true)
        let templateSource = externalAssets.appendingPathComponent("private-template.pdf")
        let letterheadSource = externalAssets.appendingPathComponent("private-letterhead.png")
        try write("%PDF- fixture", to: templateSource)
        try write("image", to: letterheadSource)
        _ = try fixture.studio.importTemplatePDF(from: templateSource)
        _ = try fixture.studio.addLetterhead(from: letterheadSource)
        fixture.approvals.add(MinutesApprovalRecord(meetingID: meeting.id, reviewerName: "Reviewer", reviewerEmail: nil,
                                                    channel: .shareSheet, versionTag: "12345678"))
        fixture.vidur.record(VidurHistoryEntry(meetingID: meeting.id, question: "Private?", answer: "Private"))
        _ = try await fixture.jobs.upsert(AnalysisJobRecord(meetingID: meeting.id, sourceFingerprint: "source",
            checkpointVersion: "1", requiredModels: []))
        defaults.set(["minutes-\(meeting.id.uuidString)"], forKey: LocalInboxReadStore.defaultsKey)
    }

    private func populateEveryFileType(_ roots: UserContentInventory, meeting: Meeting) throws {
        try write("chunk", to: roots.meetingDirectories(meeting.id)[0].appendingPathComponent("chunk-0000.caf"))
        try write("prepared", to: roots.meetingDirectories(meeting.id)[1].appendingPathComponent("chunk-0000.json"))
        try write("checkpoint", to: roots.meetingFiles(meeting.id)[0])
        try write("orphan import", to: roots.documentsRoot.appendingPathComponent("\(UUID().uuidString).wav"))
        try write("diagnostic", to: roots.documentsRoot.appendingPathComponent("BenchmarkMetrics/run.json"))
        try write("export", to: roots.temporaryRoot.appendingPathComponent("Manent-old.pdf"))
        try write("cache", to: roots.temporaryRoot.appendingPathComponent("MeetMindAudioCache/cache.m4a"))
        let recoveryStore = RecordingTakeJournalStore(
            documentsRoot: roots.documentsRoot,
            recoveryRoot: roots.recordingRecoveryRoot
        )
        let recording = roots.documentsRoot.appendingPathComponent("Recordings/private.m4a")
        _ = try recoveryStore.createBeforeRecording(meetingID: meeting.id, audioURL: recording)
    }

    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }
}
