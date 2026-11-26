import Foundation
import SwiftData
import OfflineEngineKit
import OSLog
import AVFoundation
import CryptoKit

public struct AnalysisModelStatus: Sendable, Equatable, Identifiable {
    public var id: String { profile.id }
    public let profile: ModelProfile
    public let readiness: ModelReadiness
}

public protocol AnalysisPipelineRunning: Sendable {
    func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
             model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
             progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint
    func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
             model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
             participants: [String], agenda: String?,
             progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint
    func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
             model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
             participants: [String], agenda: String?, liveCaptionEvidence: [AnalysisTurn],
             progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint
    func savedCheckpoint(meetingID: UUID) async -> MeetingAnalysisCheckpoint?
    func speakerWarning() async -> String?
    func analysisReuseCounts() async -> (reused: Int, analyzed: Int)
    func analysisFallbackSummary() async -> (chunks: Int, reason: String?)
    func stageTimings() async -> AnalysisStageTimings
}

extension AnalysisPipelineRunning {
    public func stageTimings() async -> AnalysisStageTimings { AnalysisStageTimings() }
    public func analysisReuseCounts() async -> (reused: Int, analyzed: Int) { (0, 0) }
    public func analysisFallbackSummary() async -> (chunks: Int, reason: String?) { (0, nil) }

    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
                    model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
                    participants: [String], agenda: String?, liveCaptionEvidence: [AnalysisTurn],
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        try await run(meetingID: meetingID, audio: audio, meetingDate: meetingDate, timezone: timezone,
                      languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                      reviewedTurns: reviewedTurns, participants: participants, agenda: agenda, progress: progress)
    }

    /// Conformers that predate participant/agenda context still work; the
    /// extra context only improves owner resolution in the real pipeline.
    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
                    model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
                    participants: [String], agenda: String?,
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        try await run(meetingID: meetingID, audio: audio, meetingDate: meetingDate, timezone: timezone,
                      languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                      reviewedTurns: reviewedTurns, progress: progress)
    }
}

extension MeetingAnalysisPipeline: AnalysisPipelineRunning {
    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String?,
                    model: VidurModel, stopAfterSpeakers: Bool, reviewedTurns: [AnalysisTurn],
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        try await run(meetingID: meetingID, audio: audio, meetingDate: meetingDate, timezone: timezone,
                      languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                      reviewedTurns: reviewedTurns, participants: [], agenda: nil, progress: progress)
    }
    public func speakerWarning() async -> String? { lastSpeakerWarning }
    public func stageTimings() async -> AnalysisStageTimings { lastStageTimings }
    public func analysisReuseCounts() async -> (reused: Int, analyzed: Int) { lastAnalysisReuse }
    public func analysisFallbackSummary() async -> (chunks: Int, reason: String?) {
        (lastAnalysisFallbackChunks, lastAnalysisFallbackReason)
    }
}

public enum AnalysisCoordinatorError: LocalizedError {
    case failed(AnalysisFailure)
    case modelsRequired([AnalysisModelStatus])

    public var errorDescription: String? {
        switch self {
        case .failed(let failure): return failure.message
        case .modelsRequired: return "Required on-device models must be downloaded or repaired before processing can continue."
        }
    }
}

/// The single production path for preparation, readiness, execution, checkpoint
/// commits, and final SwiftData commits. SwiftData values never leave MainActor.
@MainActor
public final class AnalysisCoordinator {
    private let context: ModelContext
    private let jobs: AnalysisJobStore
    private let pipeline: any AnalysisPipelineRunning
    private let models: OfflineModelStore
    private let profilesProvider: @Sendable () throws -> [ModelProfile]

    public init(context: ModelContext, jobs: AnalysisJobStore = .shared,
                pipeline: any AnalysisPipelineRunning = MeetingAnalysisPipeline.shared,
                models: OfflineModelStore = .shared,
                profilesProvider: @escaping @Sendable () throws -> [ModelProfile] = { try OfflineModelStore.profiles() }) {
        self.context = context
        self.jobs = jobs
        self.pipeline = pipeline
        self.models = models
        self.profilesProvider = profilesProvider
    }

    @discardableResult
    public func prepare(meetingID: UUID, languageCode: String?, model: VidurModel,
                        speakersOnly: Bool = false) async throws -> AnalysisJobRecord {
        let meeting = try fetchMeeting(meetingID)
        let profiles = try requiredProfiles(model: model, speakersOnly: speakersOnly)
        guard let audio = meeting.resolvedAudioFileURL, audio.isFileURL,
              FileManager.default.fileExists(atPath: audio.path) else {
            let failure = AnalysisFailure.stable(.sourceUnavailable)
            try await persistPreparationFailure(meeting: meeting, profiles: profiles, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        let audioFile: AVAudioFile
        do { audioFile = try AVAudioFile(forReading: audio) }
        catch {
            let failure = AnalysisFailure.stable(.audioUnreadable)
            try await persistPreparationFailure(meeting: meeting, profiles: profiles, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        guard audioFile.fileFormat.sampleRate > 0, audioFile.length > 0 else {
            let failure = AnalysisFailure.stable(.audioUnreadable)
            try await persistPreparationFailure(meeting: meeting, profiles: profiles, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        let fingerprint: String
        do {
            fingerprint = try sourceFingerprint(audio: audio, meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
                                                timezone: meeting.analysisTimezone ?? TimeZone.current.identifier,
                                                languageCode: languageCode, profiles: profiles)
        } catch {
            let failure = AnalysisFailure.stable(.audioUnreadable)
            try await persistPreparationFailure(meeting: meeting, profiles: profiles, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        if var existing = try await jobs.get(meetingID), existing.sourceFingerprint == fingerprint,
           existing.checkpointVersion == MeetingAnalysisPipeline.checkpointFormatVersion {
            existing.requiredModels = profiles.map(AnalysisModelRequirement.init)
            return try await jobs.upsert(existing)
        }
        let record = AnalysisJobRecord(meetingID: meetingID, sourceFingerprint: fingerprint,
            checkpointVersion: MeetingAnalysisPipeline.checkpointFormatVersion,
            requiredModels: profiles.map(AnalysisModelRequirement.init))
        meeting.setAudioFileURL(audio)
        meeting.duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        meeting.status = .processing
        meeting.analysisState = "ready"
        if meeting.analysisTimezone == nil { meeting.analysisTimezone = TimeZone.current.identifier }
        try context.save()
        return try await jobs.upsert(record)
    }

    public func snapshot(meetingID: UUID) async throws -> AnalysisJobRecord? {
        try await jobs.get(meetingID)
    }

    public func modelStatus(meetingID: UUID, model: VidurModel,
                            speakersOnly: Bool = false) async throws -> [AnalysisModelStatus] {
        let profiles = try requiredProfiles(model: model, speakersOnly: speakersOnly)
        var result: [AnalysisModelStatus] = []
        for profile in profiles {
            result.append(AnalysisModelStatus(profile: profile, readiness: await models.readiness(profile)))
        }
        return result
    }

    public func markModelsRequired(meetingID: UUID) async throws {
        try await jobs.setState(meetingID, state: .needsModels, stage: .preparing)
    }

    public func downloadAndVerify(meetingID: UUID, model: VidurModel, speakersOnly: Bool = false,
                                  progress: @Sendable @escaping (String, Double) -> Void,
                                  stateChanged: (@MainActor @Sendable (AnalysisJobState) -> Void)? = nil) async throws {
        try await jobs.setState(meetingID, state: .downloading, stage: .preparing)
        stateChanged?(.downloading)
        for status in try await modelStatus(meetingID: meetingID, model: model, speakersOnly: speakersOnly) where status.readiness != .ready {
            switch status.readiness {
            case .corrupt, .incompatible:
                try await models.repair(status.profile) { value in progress(status.profile.id, value) }
            default:
                try await models.install(status.profile) { value in progress(status.profile.id, value) }
            }
        }
        try await jobs.setState(meetingID, state: .verifying, stage: .preparing)
        stateChanged?(.verifying)
        let states = try await modelStatus(meetingID: meetingID, model: model, speakersOnly: speakersOnly)
        if let bad = states.first(where: { $0.readiness != .ready }) {
            let failure = AnalysisFailure.stable(.modelCorrupt, modelName: bad.profile.name)
            try await jobs.setState(meetingID, state: .failed, stage: .preparing, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        try await jobs.setState(meetingID, state: .queued, stage: .preparing)
        stateChanged?(.queued)
    }

    public func enqueue(meetingID: UUID, languageCode: String?, model: VidurModel) async throws {
        let record = try await prepare(meetingID: meetingID, languageCode: languageCode, model: model)
        _ = try await jobs.enqueue(record)
    }

    public func run(meetingID: UUID, languageCode: String?, model: VidurModel,
                    owner: AnalysisExecutionOwner, stopAfterSpeakers: Bool = false,
                    progress: (@MainActor @Sendable (MeetingAnalysisStage) -> Void)? = nil) async throws -> AnalysisJobRecord {
        _ = try await prepare(meetingID: meetingID, languageCode: languageCode, model: model,
                              speakersOnly: stopAfterSpeakers)
        let statuses = try await modelStatus(meetingID: meetingID, model: model, speakersOnly: stopAfterSpeakers)
        if statuses.contains(where: { $0.readiness != .ready }) {
            try await jobs.setState(meetingID, state: .needsModels, stage: .preparing)
            throw AnalysisCoordinatorError.modelsRequired(statuses)
        }
        let lease: AnalysisJobLease
        do { lease = try await jobs.claim(meetingID, owner: owner) }
        catch AnalysisJobStoreError.leaseConflict {
            throw AnalysisCoordinatorError.failed(.stable(.leaseConflict))
        }
        let meeting = try fetchMeeting(meetingID)
        guard let audio = meeting.resolvedAudioFileURL else {
            let failure = AnalysisFailure.stable(.sourceUnavailable)
            try? await jobs.fail(lease, failure: failure)
            throw AnalysisCoordinatorError.failed(failure)
        }
        let existing = meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }
        let reviewedTurns: [AnalysisTurn] = existing.contains(where: \.isEdited) ? existing.map {
            AnalysisTurn(id: $0.id.uuidString, text: $0.text, start: $0.startTime,
                         end: $0.endTime, speaker: $0.speaker?.recordingVoiceLabel ?? $0.speaker?.name)
        } : []
        let liveEvidence = meeting.liveCaptionEvidenceData
            .flatMap { try? JSONDecoder().decode([LiveTranscriptSegment].self, from: $0) } ?? []
        let liveCaptionEvidence = liveEvidence.enumerated().map { index, phrase in
            AnalysisTurn(id: "live-caption-\(index)", text: phrase.text,
                         start: phrase.startTime, end: phrase.endTime, speaker: nil)
        }
        let pendingCorrections = reviewedTurns.isEmpty ? nil : Self.unreviewedCorrections(
            from: meeting.offlineAnalysisData, segments: existing)
        do {
            let runStarted = Date()
            OfflineProcessingGate.begin()
            defer { OfflineProcessingGate.end() }
            var result = try await pipeline.run(meetingID: meetingID, audio: audio,
                meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
                timezone: meeting.analysisTimezone ?? TimeZone.current.identifier,
                languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                reviewedTurns: reviewedTurns,
                participants: meeting.namedAttendees.map(\.name),
                agenda: writtenAgenda(for: meeting), liveCaptionEvidence: liveCaptionEvidence) { [weak self] stage in
                    await self?.reached(stage, meetingID: meetingID, lease: lease, progress: progress)
                }
            try Task.checkCancellation()
            if !reviewedTurns.isEmpty {
                result.transcriptCorrections = pendingCorrections
            }
            if reviewedTurns.isEmpty {
                // Known voices are named before the transcript is rebuilt, so the names carry through.
                await SpeakerVoiceNaming.apply(result, to: meeting, context: context)
                replaceTranscript(of: meeting, with: result.turns)
            }
            let warning = await pipeline.speakerWarning()
            if stopAfterSpeakers {
                if result.transcriptCorrections?.isEmpty == false {
                    meeting.offlineAnalysisData = try JSONEncoder().encode(result.withoutVoiceEmbeddings())
                }
                meeting.analysisState = "speakerReview"
                try context.save()
                try await jobs.transition(lease, state: .speakerReview, stage: .speakers, warning: warning)
                try await jobs.release(lease)
                return try await requiredSnapshot(meetingID)
            }
            // Voice embeddings stay in the voice store, not in the meeting's saved analysis.
            try commitMinutes(result.withoutVoiceEmbeddings(), to: meeting)
            try context.save()
            let reuse = await pipeline.analysisReuseCounts()
            let fallback = await pipeline.analysisFallbackSummary()
            let transcriptReuse = TranscriptReuseRegistry.shared.summary(for: meetingID)
            let stages = await pipeline.stageTimings()
            let backgrounded = !ComputeEnvironment.gpuAvailable
            Logger(subsystem: "com.meetmind.app", category: "Analysis").notice(
                "Analysis stages \(stages.logDescription, privacy: .public) ended_in_background=\(backgrounded, privacy: .public)")
            Logger(subsystem: "com.meetmind.app", category: "Analysis").notice(
                "Analysis timing total_ms=\(Int(Date().timeIntervalSince(runStarted) * 1_000), privacy: .public) audio_s=\(Int(transcriptReuse?.totalSeconds ?? 0), privacy: .public) transcript_reused_s=\(Int(transcriptReuse?.reusedSeconds ?? 0), privacy: .public) minutes_chunks_reused=\(reuse.reused, privacy: .public) minutes_chunks_analyzed=\(reuse.analyzed, privacy: .public) fallback_chunks=\(fallback.chunks, privacy: .public) fallback_reason=\(fallback.reason ?? "none", privacy: .public)")
            try await jobs.complete(lease, warning: warning)
            return try await requiredSnapshot(meetingID)
        } catch is CancellationError {
            try? await commitTranscriptCheckpoint(meetingID: meetingID)
            meeting.analysisState = "paused"
            try? context.save()
            try? await jobs.pause(lease)
            throw CancellationError()
        } catch {
            try? await commitTranscriptCheckpoint(meetingID: meetingID)
            let failure = mapFailure(error)
            meeting.analysisState = "failed"
            try? context.save()
            try? await jobs.fail(lease, failure: failure)
            // OfflineError text is authored by the engine (no transcript content).
            let engineReason = (error as? OfflineError)?.errorDescription ?? String(describing: type(of: error))
            Logger(subsystem: "com.meetmind.app", category: "Analysis")
                .error("Meeting analysis failed with code \(failure.code.rawValue, privacy: .public) reason=\(engineReason, privacy: .public)")
            throw AnalysisCoordinatorError.failed(failure)
        }
    }

    private func reached(_ stage: MeetingAnalysisStage, meetingID: UUID, lease: AnalysisJobLease,
                         progress: (@MainActor @Sendable (MeetingAnalysisStage) -> Void)?) async {
        progress?(stage)
        let mapped: AnalysisStage
        switch stage {
        case .transcription: mapped = .transcription
        case .speakers:
            mapped = .speakers
            try? await commitTranscriptCheckpoint(meetingID: meetingID)
        case .analysis: mapped = .analysis
        case .completed: mapped = .saving
        }
        let warning = stage == .analysis ? await pipeline.speakerWarning() : nil
        try? await jobs.transition(lease, state: .running, stage: mapped, warning: warning)
        if let meeting = try? fetchMeeting(meetingID) {
            meeting.analysisState = stage.rawValue
            try? context.save()
        }
    }

    private func commitTranscriptCheckpoint(meetingID: UUID) async throws {
        guard let checkpoint = await pipeline.savedCheckpoint(meetingID: meetingID), !checkpoint.turns.isEmpty else { return }
        let meeting = try fetchMeeting(meetingID)
        guard !meeting.transcriptSegments.contains(where: \.isEdited) else { return }
        replaceTranscript(of: meeting, with: checkpoint.turns)
        try context.save()
    }

    /// True when the one-time prompt-example repair has not run yet.
    public static var needsPromptExampleRepair: Bool {
        !UserDefaults.standard.bool(forKey: promptExampleRepairKey)
    }
    private static let promptExampleRepairKey = "MeetMind.promptExampleRepair.v1"

    /// Earlier prompt versions let the model copy an example decision ("The Pune vendor is
    /// engaged") into real minutes. Re-sanitizes each saved chunk result against its own
    /// transcript and refreshes the minutes text of meetings where something was removed.
    ///
    /// Runs at most once: the flag is set before any work, so a failure can never turn into
    /// a crash on every launch. Only stored text changes; no summary object is deleted or
    /// created, and a meeting's review, finalized or shared state is left as it is.
    public func repairPromptExampleLeaks() {
        guard Self.needsPromptExampleRepair else { return }
        UserDefaults.standard.set(true, forKey: Self.promptExampleRepairKey)
        guard let meetings = try? context.fetch(FetchDescriptor<Meeting>()) else { return }
        func itemCount(_ result: LocalAnalysisResult) -> Int {
            result.discussion.count + result.decisions.count + result.tasks.count + result.openIssues.count
        }
        var changedAny = false
        for meeting in meetings where !meeting.isDeleted {
            guard let data = meeting.offlineAnalysisData,
                  var checkpoint = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
                  checkpoint.stage == .completed else { continue }
            let byID = Dictionary(checkpoint.turns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var changed = false
            for index in checkpoint.analysis.indices {
                var chunk = checkpoint.turns
                if let plan = checkpoint.chunkTurnIDs, index < plan.count {
                    let planned = plan[index].compactMap { byID[$0] }
                    if !planned.isEmpty { chunk = planned }
                }
                let clean = checkpoint.analysis[index].sanitized(against: chunk)
                if itemCount(clean) != itemCount(checkpoint.analysis[index]) {
                    checkpoint.analysis[index] = clean
                    changed = true
                }
            }
            guard changed else { continue }
            let previousDerivedAgenda = PlannedAgenda.derivedAgenda(meeting)
            checkpoint.minutes = nil
            let fields = minutesFields(checkpoint, for: meeting)
            guard let encoded = try? JSONEncoder().encode(fields.reduced.checkpoint) else { continue }
            meeting.offlineAnalysisData = encoded
            if let summary = meeting.summary, !summary.isDeleted, summary.modelContext != nil {
                summary.executiveSummary = fields.overview
                summary.keyPoints = fields.points
                summary.keyDecisions = fields.decisions
            }
            // An agenda the minutes filled in is refreshed; an agenda the person wrote is kept.
            let currentAgenda = PlannedAgenda.normalized(meeting.agendaText ?? "")
            if let previousDerivedAgenda, PlannedAgenda.normalized(previousDerivedAgenda) == currentAgenda,
               !fields.topicAgenda.isEmpty {
                meeting.agendaText = fields.topicAgenda
            }
            changedAny = true
        }
        if changedAny { try? context.save() }
    }

    /// The minutes text derived from a completed checkpoint, shared by the final pass and repairs.
    private static func unreviewedCorrections(from data: Data?, segments: [TranscriptSegment]) -> [TranscriptCorrection]? {
        let edited = segments.filter(\.isEdited)
        let checkpoint = data.flatMap { try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: $0) }
        return checkpoint?.transcriptCorrections?.filter { correction in
                !edited.contains {
                    abs($0.startTime - correction.start) < 0.01 && abs($0.endTime - correction.end) < 0.01
                }
            }
    }

    /// The agenda a person wrote. Template defaults and agendas the minutes filled in are not included,
    /// so the overview never feeds its own output back.
    private func writtenAgenda(for meeting: Meeting) -> String? {
        guard let planned = PlannedAgenda.planned(meeting), !isPlaceholderAgenda(planned) else { return nil }
        return planned
    }

    private func minutesFields(_ result: MeetingAnalysisCheckpoint, for meeting: Meeting)
        -> (reduced: ReducedMeetingAnalysis, overview: String, points: [String], decisions: [String], topicAgenda: String) {
        let speakerNames = MeetingSpeakerNames(meeting: meeting, store: MeetingRecordStore.shared).assignedLabels
        let zone = TimeZone(identifier: meeting.analysisTimezone ?? "") ?? TimeZone.current
        let reduced = MeetingAnalysisReducer.reduce(result, participants: meeting.namedAttendees.map(\.name),
                                                    speakerNames: speakerNames,
                                                    meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
                                                    timeZone: zone, agenda: writtenAgenda(for: meeting))
        let minutes = reduced.minutes
        var pointSource: [String] = []
        for topic in minutes.topics { pointSource.append(contentsOf: topic.discussion) }
        let structuredEvidence = minutes.topics.flatMap(\.evidence)
        pointSource.append(contentsOf: reduced.discussion.filter { point in
            !point.evidence.contains { item in
                structuredEvidence.contains { $0.turnID == item.turnID && $0.quote == item.quote }
            }
        }.map(\.text))
        var decisionSource = minutes.resolutions.map(\.text)
        if decisionSource.isEmpty { decisionSource = reduced.decisions.map(\.text) }
        let overview = minutes.topics.isEmpty || minutes.executiveSummary.isEmpty
            ? reduced.executiveSummary : minutes.executiveSummary
        let topicAgenda = minutes.topics.isEmpty ? reduced.agendaTopics.joined(separator: "\n") : minutes.agendaText
        return (reduced, overview, uniqueTexts(pointSource), uniqueTexts(decisionSource), topicAgenda)
    }

    public func reprocessMinutes(meetingID: UUID, model: VidurModel) async throws {
        let meeting = try fetchMeeting(meetingID)
        let turns = savedTurns(for: meeting)
        let previousAnalysis = meeting.offlineAnalysisData
        let previousAgenda = meeting.agendaText
        let previousGeneratedAgenda = previousAnalysis.flatMap {
            try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: $0)
        }?.minutes?.agendaText
        let hasGeneratedAgenda = previousGeneratedAgenda?.isEmpty == false
            && previousGeneratedAgenda == previousAgenda
        let agendaText = (previousAgenda ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let replaceAgenda = hasGeneratedAgenda || agendaText.isEmpty || isPlaceholderAgenda(agendaText)
        guard meeting.status == .completed, !turns.isEmpty else {
            throw OfflineError.unavailable("A saved transcript is required to reprocess minutes.")
        }
        let modelProfile = try requiredProfiles(model: model, speakersOnly: false)[2]
        guard await models.readiness(modelProfile) == .ready else {
            throw OfflineError.unavailable("Download or repair the Minutes & Vidur model in Settings, then try again.")
        }
        OfflineProcessingGate.begin()
        defer { OfflineProcessingGate.end() }
        let corrections = Self.unreviewedCorrections(from: previousAnalysis, segments: meeting.orderedTranscriptSegments)
        let result = try await MeetingAnalysisPipeline.shared.reprocessTranscript(
            meetingID: meetingID, turns: turns, meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
            timezone: meeting.analysisTimezone ?? TimeZone.current.identifier, model: model,
            participants: meeting.namedAttendees.map(\.name), agenda: replaceAgenda ? nil : previousAgenda,
            corrections: corrections)
        try Task.checkCancellation()
        let current = try fetchMeeting(meetingID)
        guard current.status == .completed, current.offlineAnalysisData == previousAnalysis,
              current.agendaText == previousAgenda, savedTurns(for: current) == turns else {
            throw OfflineError.unavailable("The meeting changed while reprocessing. Open it again to retry.")
        }
        let fields = minutesFields(result, for: current)
        let analysisData = try JSONEncoder().encode(fields.reduced.checkpoint)
        let store = MeetingRecordStore.shared
        let previousRecord = store.record(for: meetingID)
        var updatedRecord = previousRecord
        if !previousRecord.deciderIDs.isEmpty {
            updatedRecord.remapDeciders(oldDecisions: current.summary?.keyDecisions ?? [], newDecisions: fields.decisions)
        }
        let decidersChanged = updatedRecord.deciderIDs != previousRecord.deciderIDs
        try context.save()
        if decidersChanged { try store.update(meetingID) { $0.deciderIDs = updatedRecord.deciderIDs } }
        applyMinutes(overview: fields.overview, points: fields.points, decisions: fields.decisions,
                     analysisData: analysisData, to: current)
        if replaceAgenda {
            current.agendaText = fields.topicAgenda.isEmpty ? nil : fields.topicAgenda
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            if decidersChanged { try? store.update(meetingID) { $0.deciderIDs = previousRecord.deciderIDs } }
            throw error
        }
    }

    private func savedTurns(for meeting: Meeting) -> [AnalysisTurn] {
        let names = MeetingSpeakerNames(meeting: meeting, store: MeetingRecordStore.shared).assignedLabels
        return meeting.orderedTranscriptSegments.compactMap { segment -> AnalysisTurn? in
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let label = segment.speaker?.recordingVoiceLabel
            let identified = label.flatMap { names[$0] } ?? label ?? segment.speaker?.name
            return AnalysisTurn(id: segment.id.uuidString, text: segment.text, start: segment.startTime,
                end: segment.endTime, speaker: identified)
        }
    }

    private func commitMinutes(_ result: MeetingAnalysisCheckpoint, to meeting: Meeting) throws {
        // Names the user gave attendees let the reducer attach an owner to requests
        // ("Pawan, can you ...") and to first-person promises. Generic labels never count.
        // Topic bullets are rephrased English; a model discussion point never replaces them.
        let fields = minutesFields(result, for: meeting)
        let analysisData = try JSONEncoder().encode(fields.reduced.checkpoint)
        applyMinutes(overview: fields.overview, points: fields.points, decisions: fields.decisions,
                     analysisData: analysisData, to: meeting)
        // An empty or placeholder agenda is filled with the topics heard in the meeting; the user can edit it later.
        let currentAgenda = (meeting.agendaText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let topicAgenda = fields.topicAgenda
        let seriesMeetings = meeting.seriesID == nil ? [] : ((try? context.fetch(FetchDescriptor<Meeting>())) ?? [])
        let copiedAgenda = PlannedAgenda.isCopiedFromSeries(meeting, among: seriesMeetings)
        if !topicAgenda.isEmpty, currentAgenda.isEmpty || isPlaceholderAgenda(currentAgenda) || copiedAgenda {
            meeting.agendaText = topicAgenda
        } else if copiedAgenda {
            meeting.agendaText = nil
        }
    }

    private func applyMinutes(overview: String, points: [String], decisions: [String],
                              analysisData: Data, to meeting: Meeting) {
        // The existing summary is updated in place. Deleting it and attaching a new one in
        // the same change tripped a SwiftData assertion on launch-time repairs.
        if let summary = meeting.summary, !summary.isDeleted, summary.modelContext != nil {
            summary.executiveSummary = overview
            summary.keyPoints = points
            summary.keyDecisions = decisions
            summary.generatedAt = Date()
        } else {
            meeting.summary = Summary(executiveSummary: overview,
                keyPoints: points, keyDecisions: decisions, meeting: meeting)
        }
        // Tasks stay review suggestions (never auto-accepted); owner and context are preassigned in the checkpoint.
        // Suggested attendees live in `minutes.suggestedAttendees` and are never added automatically.
        meeting.offlineAnalysisData = analysisData
        meeting.status = .completed
        meeting.analysisState = "completed"
        meeting.minutesNeedFinalization = true
    }

    /// True when the agenda is one of the built-in template agendas the user never edited.
    private func isPlaceholderAgenda(_ agenda: String) -> Bool {
        let key = normalizedAgendaKey(agenda)
        for template in MeetingTemplateType.allCases where normalizedAgendaKey(template.defaultAgenda) == key {
            return true
        }
        return false
    }

    private func normalizedAgendaKey(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func replaceTranscript(of meeting: Meeting, with turns: [AnalysisTurn]) {
        // Voice naming lives in MeetingRecordStore; the editor maps each diarization
        // label back to the person it was assigned to instead of recreating "Speaker N".
        MeetingPeopleEditor.replaceTranscript(of: meeting, with: turns, context: context,
                                              store: MeetingRecordStore.shared)
    }

    private func fetchMeeting(_ id: UUID) throws -> Meeting {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let meeting = try context.fetch(descriptor).first else { throw MeetingError.meetingNotFound }
        return meeting
    }

    private func requiredProfiles(model: VidurModel, speakersOnly: Bool) throws -> [ModelProfile] {
        let profiles = try profilesProvider()
        return try ["whisper-large", "diarization", model.rawValue]
            .prefix(speakersOnly ? 2 : 3).map { id in
                guard let profile = profiles.first(where: { $0.id == id }) else {
                    throw AnalysisCoordinatorError.failed(.stable(.modelAbsent))
                }
                return profile
            }
    }

    private func persistPreparationFailure(meeting: Meeting, profiles: [ModelProfile],
                                           failure: AnalysisFailure) async throws {
        var record = AnalysisJobRecord(meetingID: meeting.id, sourceFingerprint: "unavailable",
            checkpointVersion: MeetingAnalysisPipeline.checkpointFormatVersion,
            state: .failed, requiredModels: profiles.map(AnalysisModelRequirement.init))
        record.failure = failure
        meeting.analysisState = "failed"
        try context.save()
        _ = try await jobs.upsert(record)
    }

    private func sourceFingerprint(audio: URL, meetingDate: Date, timezone: String,
                                   languageCode: String?, profiles: [ModelProfile]) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: audio.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let source = "\(size)|\(modified)|\(meetingDate.timeIntervalSinceReferenceDate)|\(timezone)|\(languageCode ?? "auto")|\(profiles.map { "\($0.id):\($0.revision)" }.joined(separator: ","))|\(MeetingAnalysisPipeline.checkpointFormatVersion)"
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func requiredSnapshot(_ meetingID: UUID) async throws -> AnalysisJobRecord {
        guard let snapshot = try await jobs.get(meetingID) else { throw AnalysisJobStoreError.missingJob }
        return snapshot
    }

    private func mapFailure(_ error: Error) -> AnalysisFailure {
        if let coordinator = error as? AnalysisCoordinatorError,
           case .failed(let failure) = coordinator { return failure }
        if let storeError = error as? AnalysisJobStoreError {
            return .stable(storeError == .corrupt ? .jobStoreCorrupt : .leaseConflict)
        }
        if let offline = error as? OfflineError {
            if case .memoryBudget = offline { return .stable(.resourceConstrained) }
        }
        let description = error.localizedDescription.lowercased()
        if description.contains("no speech") { return .stable(.noSpeech) }
        if description.contains("checkpoint") && description.contains("invalid") { return .stable(.checkpointCorrupt) }
        if description.contains("warm") || description.contains("memory") { return .stable(.resourceConstrained) }
        return .stable(.processingFailed)
    }

    private func uniqueTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { seen.insert($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }
}
