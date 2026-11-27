import XCTest
import Foundation
import SwiftData
import OfflineEngineKit
@testable import MeetMind

/// Voice profile storage and automatic voice naming. Uses synthetic 8-dimensional embeddings only.
@MainActor
final class SpeakerVoiceNamingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var records: MeetingRecordStore!
    private var store: VoiceProfileStore!
    private var directory: URL!
    private var defaults: UserDefaults!
    private let suiteName = "SpeakerVoiceNamingTests"

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.createInMemoryContainer()
        context = container.mainContext
        records = MeetingRecordStore(fileURL: nil)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceStore-\(UUID().uuidString)")
        store = VoiceProfileStore(fileURL: directory.appendingPathComponent("voices.json"))
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        store = nil; records = nil; context = nil; container = nil; defaults = nil
        try await super.tearDown()
    }

    private func vector(_ index: Int, _ weight: Float = 1, other: Int? = nil, _ otherWeight: Float = 0) -> [Float] {
        var result = [Float](repeating: 0, count: 8)
        result[index] = weight
        if let other { result[other] = otherWeight }
        return result
    }

    private struct Scene {
        let meeting: Meeting
        let neha: Speaker
    }

    private func makeScene() throws -> Scene {
        let meeting = Meeting(title: "Sync", duration: 60, status: .completed)
        context.insert(meeting)
        let neha = Speaker(name: "Neha")
        context.insert(neha)
        meeting.addParticipant(neha)
        try context.save()
        return Scene(meeting: meeting, neha: neha)
    }

    private func checkpoint(_ embedding: [Float], seconds: Double = 20, revision: String = "rev-1") -> MeetingAnalysisCheckpoint {
        MeetingAnalysisCheckpoint(sourceSignature: "s", stage: .analysis, turns: [],
                                  speakers: [SpeakerSpan(speaker: "S1", start: 0, end: seconds)],
                                  analysis: [], analyzedChunks: 0,
                                  speakerEmbeddings: ["S1": embedding], speakerEmbeddingModel: revision)
    }

    // MARK: Store

    func test_store_roundTripsProfilesAndMeetingRecords() throws {
        let person = UUID(), meeting = UUID()
        XCTAssertEqual(try store.learn(vector(0), personID: person, revision: "rev-1"), .created)
        try store.setRecord(MeetingVoiceRecord(modelRevision: "rev-1", centroids: ["S1": vector(0)],
                                               speechSeconds: ["S1": 12]), for: meeting)
        let reopened = VoiceProfileStore(fileURL: directory.appendingPathComponent("voices.json"))
        XCTAssertEqual(reopened.profiles(revision: "rev-1").map(\.personID), [person])
        XCTAssertEqual(reopened.record(for: meeting)?.speechSeconds["S1"], 12)
    }

    func test_store_isExcludedFromBackupAndProtected() throws {
        try store.learn(vector(0), personID: UUID(), revision: "rev-1")
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func test_store_modelRevisionChangeInvalidatesProfiles() throws {
        let person = UUID()
        try store.learn(vector(0), personID: person, revision: "rev-1")
        XCTAssertTrue(store.profiles(revision: "rev-2").isEmpty, "Profiles from another model revision are not comparable")
        try store.learn(vector(1), personID: person, revision: "rev-2")
        XCTAssertTrue(store.profiles(revision: "rev-1").isEmpty)
        XCTAssertEqual(store.profiles(revision: "rev-2").first?.sampleCount, 1)
    }

    func test_store_rejectedOutlierIsNotSaved() throws {
        let person = UUID()
        try store.learn(vector(0), personID: person, revision: "rev-1")
        XCTAssertEqual(try store.learn(vector(1), personID: person, revision: "rev-1"), .rejectedOutlier)
        XCTAssertEqual(store.profile(for: person, revision: "rev-1")?.sampleCount, 1)
    }

    func test_store_removeMeetingAndEraseAll() throws {
        let meeting = UUID(), other = UUID()
        try store.learn(vector(0), personID: UUID(), revision: "rev-1")
        let record = MeetingVoiceRecord(modelRevision: "rev-1", centroids: [:], speechSeconds: [:])
        try store.setRecord(record, for: meeting)
        try store.setRecord(record, for: other)
        try store.removeMeeting(meeting)
        XCTAssertFalse(store.hasMeeting(meeting))
        XCTAssertTrue(store.hasMeeting(other))
        let file = directory.appendingPathComponent("voices.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try store.eraseAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(VoiceProfileStore(fileURL: file).isEmpty)
    }

    func test_store_corruptFileStartsEmptyInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("broken.json")
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(VoiceProfileStore(fileURL: file).isEmpty)
    }

    // MARK: Automatic naming

    func test_apply_namesAConfidentVoiceAndRecordsTheAssignment() async throws {
        let scene = try makeScene()
        try store.learn(vector(0), personID: scene.neha.id, revision: "rev-1")
        let matches = await SpeakerVoiceNaming.apply(checkpoint(vector(0, 0.9, other: 1, 0.43589)), to: scene.meeting,
                                                     context: context, store: store, records: records, defaults: defaults)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.status, .auto)
        XCTAssertEqual(matches.first?.personID, scene.neha.id)
        XCTAssertEqual(records.record(for: scene.meeting.id).voiceAssignments.map(\.label), ["S1"])
        XCTAssertEqual(records.record(for: scene.meeting.id).voiceAssignments.first?.personID, scene.neha.id)
        XCTAssertEqual(SpeakerVoiceNaming.match(forLabel: "S1", meetingID: scene.meeting.id, store: store)?.status, .auto)
    }

    func test_apply_onlySuggestsAMediumMatchAndDoesNotAssign() async throws {
        let scene = try makeScene()
        try store.learn(vector(0), personID: scene.neha.id, revision: "rev-1")
        let matches = await SpeakerVoiceNaming.apply(checkpoint(vector(0, 0.62, other: 1, 0.7846)), to: scene.meeting,
                                                     context: context, store: store, records: records, defaults: defaults)
        XCTAssertEqual(matches.first?.status, .suggested)
        XCTAssertTrue(records.record(for: scene.meeting.id).voiceAssignments.isEmpty)
        XCTAssertEqual(SpeakerVoiceNaming.match(forLabel: "S1", meetingID: scene.meeting.id, store: store)?.personID,
                       scene.neha.id)
    }

    func test_apply_shortVoiceAndUnknownVoiceStayUnnamed() async throws {
        let scene = try makeScene()
        try store.learn(vector(0), personID: scene.neha.id, revision: "rev-1")
        let short = await SpeakerVoiceNaming.apply(checkpoint(vector(0), seconds: 2), to: scene.meeting,
                                                   context: context, store: store, records: records, defaults: defaults)
        XCTAssertTrue(short.isEmpty)
        let stranger = await SpeakerVoiceNaming.apply(checkpoint(vector(3, 1, other: 0, 0.1)), to: scene.meeting,
                                                      context: context, store: store, records: records, defaults: defaults)
        XCTAssertTrue(stranger.isEmpty)
        XCTAssertTrue(records.record(for: scene.meeting.id).voiceAssignments.isEmpty)
    }

    func test_apply_neverOverridesAVoiceTheUserAlreadyAssignedAndDoesNotRepeatOnRerun() async throws {
        let scene = try makeScene()
        let other = Speaker(name: "Omar")
        context.insert(other)
        scene.meeting.addParticipant(other)
        try context.save()
        try store.learn(vector(0), personID: scene.neha.id, revision: "rev-1")
        try records.update(scene.meeting.id) { $0.voiceAssignments = [VoiceAssignment(label: "S1", personID: other.id, segmentIDs: [])] }
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0)), to: scene.meeting, context: context,
                                           store: store, records: records, defaults: defaults)
        XCTAssertEqual(records.record(for: scene.meeting.id).voiceAssignments.map(\.personID), [other.id])

        // The user undoes a name. A later run over the same voices must not bring it back.
        let again = try makeScene()
        try store.learn(vector(0), personID: again.neha.id, revision: "rev-1")
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0)), to: again.meeting, context: context,
                                           store: store, records: records, defaults: defaults)
        XCTAssertEqual(records.record(for: again.meeting.id).voiceAssignments.count, 1)
        try records.update(again.meeting.id) { $0.voiceAssignments = [] }
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0)), to: again.meeting, context: context,
                                           store: store, records: records, defaults: defaults)
        XCTAssertTrue(records.record(for: again.meeting.id).voiceAssignments.isEmpty)
    }

    func test_apply_prefersMeetingAttendeesOverOtherKnownPeople() async throws {
        let scene = try makeScene()
        let outsider = Speaker(name: "Zed")
        context.insert(outsider)
        try context.save()
        try store.learn(vector(1), personID: outsider.id, revision: "rev-1")
        try store.learn(vector(0), personID: scene.neha.id, revision: "rev-1")
        let matches = await SpeakerVoiceNaming.apply(checkpoint(vector(1, 0.9, other: 2, 0.43589)), to: scene.meeting,
                                                     context: context, store: store, records: records, defaults: defaults)
        XCTAssertEqual(matches.first?.personID, outsider.id)
        XCTAssertEqual(matches.first?.status, .suggested, "Someone not in the meeting is offered, never applied")
        XCTAssertTrue(records.record(for: scene.meeting.id).voiceAssignments.isEmpty)
    }

    func test_apply_withoutEmbeddingsDoesNothing() async throws {
        let scene = try makeScene()
        let plain = MeetingAnalysisCheckpoint(sourceSignature: "s", stage: .analysis, turns: [], speakers: [],
                                              analysis: [], analyzedChunks: 0)
        let matches = await SpeakerVoiceNaming.apply(plain, to: scene.meeting, context: context,
                                                     store: store, records: records, defaults: defaults)
        XCTAssertTrue(matches.isEmpty)
        XCTAssertFalse(store.hasMeeting(scene.meeting.id))
    }

    // MARK: Learning

    func test_learn_teachesTheAssignedPersonOnceAndSkipsShortVoices() async throws {
        let installed = await MeetingAnalysisPipeline.shared.diarizationModelRevision()
        let revision = try XCTUnwrap(installed, "The bundled model manifest must list the diarization model")
        let scene = try makeScene()
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0), revision: revision), to: scene.meeting, context: context,
                                           store: store, records: records, defaults: defaults)
        try records.update(scene.meeting.id) {
            $0.voiceAssignments = [VoiceAssignment(label: "S1", personID: scene.neha.id, segmentIDs: [])]
        }
        await SpeakerVoiceNaming.learn(labels: ["S1"], meeting: scene.meeting, store: store, records: records)
        XCTAssertEqual(store.profile(for: scene.neha.id, revision: revision)?.sampleCount, 1)
        await SpeakerVoiceNaming.learn(labels: ["S1"], meeting: scene.meeting, store: store, records: records)
        XCTAssertEqual(store.profile(for: scene.neha.id, revision: revision)?.sampleCount, 1, "One voice is learned once")

        let shortScene = try makeScene()
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0), seconds: 4, revision: revision), to: shortScene.meeting,
                                           context: context, store: store, records: records, defaults: defaults)
        try records.update(shortScene.meeting.id) {
            $0.voiceAssignments = [VoiceAssignment(label: "S1", personID: shortScene.neha.id, segmentIDs: [])]
        }
        await SpeakerVoiceNaming.learn(labels: ["S1"], meeting: shortScene.meeting, store: store, records: records)
        XCTAssertNil(store.profile(for: shortScene.neha.id, revision: revision), "Under 6 s of speech teaches nothing")
    }

    func test_learn_ignoresVoicesFromAnOlderModelRevision() async throws {
        let scene = try makeScene()
        _ = await SpeakerVoiceNaming.apply(checkpoint(vector(0), revision: "retired-revision"), to: scene.meeting,
                                           context: context, store: store, records: records, defaults: defaults)
        try records.update(scene.meeting.id) {
            $0.voiceAssignments = [VoiceAssignment(label: "S1", personID: scene.neha.id, segmentIDs: [])]
        }
        await SpeakerVoiceNaming.learn(labels: ["S1"], meeting: scene.meeting, store: store, records: records)
        XCTAssertTrue(store.profiles(revision: "retired-revision").isEmpty)
    }

    func test_checkpointCopyKeptInTheMeetingHasNoEmbeddings() {
        let stripped = checkpoint(vector(0)).withoutVoiceEmbeddings()
        XCTAssertNil(stripped.speakerEmbeddings)
        XCTAssertNil(stripped.speakerEmbeddingModel)
    }
}
