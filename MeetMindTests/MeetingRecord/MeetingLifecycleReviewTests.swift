import XCTest
import SwiftData
@testable import MeetMind

@MainActor
final class MeetingLifecycleReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testResolverCoversEveryLifecycleAndCanonicalDestination() {
        func input(status: MeetingStatus = .processing, analysis: String? = nil,
                   summary: Bool = false, transcript: Bool = false, typed: Bool = false,
                   needsFinalization: Bool? = nil, current: String? = nil, finalized: String? = nil,
                   start: Date? = nil, audio: Bool = false) -> MeetingLifecycleInput {
            MeetingLifecycleInput(status: status, scheduledStartTime: start, hasAudio: audio,
                                  hasTranscript: transcript, hasSummary: summary, hasTypedNotesSource: typed,
                                  analysisState: analysis, minutesNeedFinalization: needsFinalization,
                                  currentFingerprint: current, finalizedFingerprint: finalized, now: now)
        }

        let cases: [(MeetingLifecycleInput, MeetingLifecycleState, MeetingDestination)] = [
            (input(status: .scheduled, start: now.addingTimeInterval(60)), .scheduled, .plan),
            (input(status: .scheduled, start: now), .readyToRecord, .captureSetup),
            (input(status: .recording), .recording, .recording),
            (input(audio: true), .saved, .processing),
            (input(analysis: "needsModels"), .needsModels, .processing),
            (input(analysis: "queued"), .queued, .processing),
            (input(analysis: "transcription"), .processing, .processing),
            (input(analysis: "failed"), .failed, .processing),
            (input(analysis: "speakerReview"), .speakerReview, .processing),
            (input(summary: true, transcript: true, needsFinalization: true), .draftReview, .reviewChecklist),
            (input(summary: true, transcript: true, current: "same", finalized: "same"), .finalized, .finalMinutes)
        ]

        for (value, state, destination) in cases {
            let resolution = MeetingLifecycleResolver.resolve(value)
            XCTAssertEqual(resolution.state, state)
            XCTAssertEqual(resolution.destination, destination)
        }
    }

    func testResolverTreatsTypedNotesAsReviewableAndInvalidatesChangedFingerprint() {
        let notes = MeetingLifecycleInput(status: .completed, hasSummary: true, hasTypedNotesSource: true,
                                          minutesNeedFinalization: true, now: now)
        XCTAssertEqual(MeetingLifecycleResolver.resolve(notes).state, .draftReview)

        let changed = MeetingLifecycleInput(status: .completed, hasTranscript: true, hasSummary: true,
                                            currentFingerprint: "new", finalizedFingerprint: "old", now: now)
        XCTAssertEqual(MeetingLifecycleResolver.resolve(changed).state, .draftReview)
    }

    func testOldFinalizedMeetingRemainsFinalizedAndRequestsBootstrap() {
        let old = MeetingLifecycleInput(status: .completed, hasTranscript: true, hasSummary: true,
                                        minutesNeedFinalization: false, now: now)
        let result = MeetingLifecycleResolver.resolve(old)
        XCTAssertEqual(result.state, .finalized)
        XCTAssertEqual(result.destination, .finalMinutes)
        XCTAssertTrue(result.isLegacyFinalized)
    }

    func testChecklistRequiresSourceTasksAndExplicitOptionalAcknowledgements() {
        let content = snapshot(source: .transcript, agenda: "", attendance: [], decisions: [],
                               unknownVoices: 1, pendingTasks: 1)
        var acknowledgements: Set<ReviewAcknowledgement> = [
            .acceptUnknownVoices, .acceptNoAgenda, .acceptNoAttendance, .acceptNoDecisions
        ]
        XCTAssertFalse(MinutesReviewChecklist.evaluate(content: content, acknowledgements: acknowledgements).canFinalize)

        let reviewedTasks = snapshot(source: .transcript, agenda: "", attendance: [], decisions: [],
                                     unknownVoices: 1, pendingTasks: 0)
        XCTAssertEqual(content.fingerprint, reviewedTasks.fingerprint,
                       "Pending suggestion metadata is a review gate, not finalized document content")
        XCTAssertTrue(MinutesReviewChecklist.evaluate(content: reviewedTasks, acknowledgements: acknowledgements).canFinalize)

        acknowledgements.remove(.acceptUnknownVoices)
        XCTAssertFalse(MinutesReviewChecklist.evaluate(content: reviewedTasks, acknowledgements: acknowledgements).canFinalize)
    }

    func testTypedNotesDoNotRequireSpeakerAcknowledgement() {
        let content = snapshot(source: .typedNotes, agenda: "Plan", attendance: ["Sam|present"],
                               decisions: ["Ship"], unknownVoices: 3, pendingTasks: 0)
        let acknowledgements: Set<ReviewAcknowledgement> = [.reviewedAgenda, .reviewedAttendance, .reviewedDecisions]
        XCTAssertTrue(MinutesReviewChecklist.evaluate(content: content, acknowledgements: acknowledgements).canFinalize)
    }

    func testFingerprintIsStableAndMaterialEditsInvalidateFinalization() throws {
        let container = try ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "Review", createdAt: now, status: .completed)
        container.mainContext.insert(meeting)
        let summary = Summary(executiveSummary: "Discussion", keyPoints: ["Point"], keyDecisions: ["Decide"])
        container.mainContext.insert(summary)
        meeting.summary = summary
        let speaker = Speaker(name: "Sam")
        container.mainContext.insert(speaker)
        meeting.addParticipant(speaker)
        let segment = TranscriptSegment(text: "Hello", startTime: 2, endTime: 3, speaker: speaker)
        container.mainContext.insert(segment)
        meeting.addTranscriptSegment(segment)
        let action = ActionItem(title: "Send notes", isCompleted: false, dueDate: now, assignee: speaker)
        container.mainContext.insert(action)
        meeting.addActionItem(action)
        meeting.agendaText = "Agenda"
        try container.mainContext.save()

        let first = MinutesReviewContentSnapshot.make(from: meeting).fingerprint
        let second = MinutesReviewContentSnapshot.make(from: meeting).fingerprint
        XCTAssertEqual(first, second)

        action.isCompleted = true
        let changed = MinutesReviewContentSnapshot.make(from: meeting).fingerprint
        XCTAssertNotEqual(first, changed)
        let result = MeetingLifecycleResolver.resolve(MeetingLifecycleInput(
            status: .completed, hasTranscript: true, hasSummary: true,
            currentFingerprint: changed, finalizedFingerprint: first, now: now))
        XCTAssertEqual(result.state, .draftReview)
    }

    func testReviewStorePersistsAcknowledgementsFingerprintAndLifecycleRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("review.json")
        let meetingID = UUID()

        let first = ReviewStateStore(fileURL: url)
        try first.setAcknowledgement(.acceptUnknownVoices, accepted: true, meetingID: meetingID,
                                     contentFingerprint: "content")
        try first.finalize(meetingID: meetingID, fingerprint: "fingerprint", at: now)

        let reloaded = ReviewStateStore(fileURL: url)
        let saved = try reloaded.record(for: meetingID)
        XCTAssertEqual(saved.acknowledgements, [.acceptUnknownVoices])
        XCTAssertEqual(saved.acknowledgements(validFor: "content"), [.acceptUnknownVoices])
        XCTAssertTrue(saved.acknowledgements(validFor: "changed").isEmpty)
        XCTAssertEqual(saved.finalizationFingerprint, "fingerprint")
        XCTAssertEqual(saved.finalizedAt, now)

        try reloaded.remove(meetingID: meetingID)
        XCTAssertNil(try reloaded.record(for: meetingID).finalizationFingerprint)
        try reloaded.setAcknowledgement(.acceptNoAgenda, accepted: true, meetingID: UUID(),
                                        contentFingerprint: "other")
        try reloaded.eraseAll()
        XCTAssertTrue(reloaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testVidurMeetingHistoryLoadsFromPersistedPreferences() throws {
        let suiteName = "VidurStageCHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let meetingID = UUID()

        VidurPreferences(defaults: defaults).record(
            VidurHistoryEntry(meetingID: meetingID, question: "What changed?", answer: "The date changed.", askedAt: now)
        )

        let reloaded = VidurPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.history(for: meetingID).map(\.question), ["What changed?"])
        XCTAssertEqual(reloaded.history(for: UUID()), [])
    }

    private func snapshot(source: MinutesSourceKind, agenda: String, attendance: [String], decisions: [String],
                          unknownVoices: Int, pendingTasks: Int) -> MinutesReviewContentSnapshot {
        MinutesReviewContentSnapshot(source: source, agenda: agenda, attendance: attendance,
                                     transcript: [], notes: [], discussion: [], decisions: decisions, actions: [],
                                     unknownVoiceCount: unknownVoices, pendingTaskSuggestionCount: pendingTasks)
    }
}
