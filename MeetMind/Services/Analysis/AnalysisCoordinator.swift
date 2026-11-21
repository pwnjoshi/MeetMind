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
    func savedCheckpoint(meetingID: UUID) async -> MeetingAnalysisCheckpoint?
    func speakerWarning() async -> String?
    func analysisReuseCounts() async -> (reused: Int, analyzed: Int)
}

extension AnalysisPipelineRunning {
    public func analysisReuseCounts() async -> (reused: Int, analyzed: Int) { (0, 0) }

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
    public func analysisReuseCounts() async -> (reused: Int, analyzed: Int) { lastAnalysisReuse }
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
        do {
            let runStarted = Date()
            OfflineProcessingGate.begin()
            defer { OfflineProcessingGate.end() }
            let result = try await pipeline.run(meetingID: meetingID, audio: audio,
                meetingDate: meeting.scheduledStartTime ?? meeting.createdAt,
                timezone: meeting.analysisTimezone ?? TimeZone.current.identifier,
                languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                reviewedTurns: reviewedTurns,
                participants: meeting.namedAttendees.map(\.name),
                agenda: meeting.agendaText) { [weak self] stage in
                    await self?.reached(stage, meetingID: meetingID, lease: lease, progress: progress)
                }
            try Task.checkCancellation()
            if reviewedTurns.isEmpty { replaceTranscript(of: meeting, with: result.turns) }
            let warning = await pipeline.speakerWarning()
            if stopAfterSpeakers {
                meeting.analysisState = "speakerReview"
                try context.save()
                try await jobs.transition(lease, state: .speakerReview, stage: .speakers, warning: warning)
                try await jobs.release(lease)
                return try await requiredSnapshot(meetingID)
            }
            try commitMinutes(result, to: meeting)
            try context.save()
            let reuse = await pipeline.analysisReuseCounts()
            let transcriptReuse = TranscriptReuseRegistry.shared.summary(for: meetingID)
            Logger(subsystem: "com.meetmind.app", category: "Analysis").notice(
                "Analysis timing total_ms=\(Int(Date().timeIntervalSince(runStarted) * 1_000), privacy: .public) audio_s=\(Int(transcriptReuse?.totalSeconds ?? 0), privacy: .public) transcript_reused_s=\(Int(transcriptReuse?.reusedSeconds ?? 0), privacy: .public) minutes_chunks_reused=\(reuse.reused, privacy: .public) minutes_chunks_analyzed=\(reuse.analyzed, privacy: .public)")
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
            Logger(subsystem: "com.meetmind.app", category: "Analysis")
                .error("Meeting analysis failed with code \(failure.code.rawValue, privacy: .public)")
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

    private func commitMinutes(_ result: MeetingAnalysisCheckpoint, to meeting: Meeting) throws {
        // Names the user gave attendees let the reducer attach an owner to requests
        // ("Pawan, can you ...") and to first-person promises. Generic labels never count.
        var speakerNames: [String: String] = [:]
        for person in meeting.namedAttendees {
            if let label = person.recordingVoiceLabel, !label.isEmpty { speakerNames[label] = person.name }
        }
        let reduced = MeetingAnalysisReducer.reduce(result, participants: meeting.namedAttendees.map(\.name),
                                                    speakerNames: speakerNames)
        // Open issues live in the checkpoint as their own list; the minutes
        // content builder renders them in a dedicated Open Issues section.
        let points = uniqueTexts(reduced.discussion.map(\.text))
        let decisions = reduced.decisions.map(\.text)
        if let old = meeting.summary { context.delete(old) }
        meeting.summary = Summary(executiveSummary: reduced.executiveSummary,
            keyPoints: points, keyDecisions: decisions, meeting: meeting)
        meeting.offlineAnalysisData = try JSONEncoder().encode(reduced.checkpoint)
        meeting.status = .completed
        meeting.analysisState = "completed"
        meeting.minutesNeedFinalization = true
    }

    private func replaceTranscript(of meeting: Meeting, with turns: [AnalysisTurn]) {
        let old = meeting.transcriptSegments
        meeting.transcriptSegments.removeAll()
        for segment in old { context.delete(segment) }
        var speakers: [String: Speaker] = [:]
        for (index, turn) in turns.enumerated() {
            var speaker: Speaker?
            if let label = turn.speaker {
                if let existing = speakers[label] ?? meeting.participants.first(where: {
                    $0.recordingVoiceLabel == label || ($0.recordingVoiceLabel == nil && $0.name == label)
                }) {
                    existing.recordingVoiceLabel = label
                    speakers[label] = existing
                    speaker = existing
                } else {
                    let created = Speaker(name: label)
                    created.recordingVoiceLabel = label
                    context.insert(created)
                    meeting.addParticipant(created)
                    speakers[label] = created
                    speaker = created
                }
            }
            meeting.addTranscriptSegment(TranscriptSegment(text: turn.text, startTime: turn.start,
                endTime: turn.end, confidence: 0, speaker: speaker, meeting: meeting, sequenceIndex: index))
        }
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
