import Foundation
import Darwin
import AVFoundation

// Repeatable on-device evaluation support. Nothing here is reachable from the normal
// meeting flow: the app calls it only from the USB-triggered `--offline-evaluation`
// launch mode. It runs the production pipeline and reducer on an audio file with a
// private checkpoint root, so it never reads or writes a user's meeting checkpoints.

/// Process memory in use, as iOS accounts it for jetsam (`phys_footprint`).
public enum EvaluationMemory {
    public static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// Samples the footprint on a timer and keeps the maximum. The sampling period (default
/// 200 ms) bounds how short a spike can be missed, so the value is a lower bound of the true peak.
public final class EvaluationPeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64
    private var sampler: Task<Void, Never>?

    public init() { peak = EvaluationMemory.footprintBytes() }

    public func start(intervalMilliseconds: UInt64 = 200) {
        lock.lock()
        defer { lock.unlock() }
        guard sampler == nil else { return }
        sampler = Task.detached { [weak self] in
            while !Task.isCancelled {
                self?.record()
                try? await Task.sleep(nanoseconds: intervalMilliseconds * 1_000_000)
            }
        }
    }

    public func record() {
        let value = EvaluationMemory.footprintBytes()
        lock.lock()
        if value > peak { peak = value }
        lock.unlock()
    }

    /// Stops sampling and returns the highest footprint seen, in bytes.
    public func stop() -> UInt64 {
        lock.lock()
        sampler?.cancel()
        sampler = nil
        lock.unlock()
        record()
        lock.lock()
        defer { lock.unlock() }
        return peak
    }
}

/// Wall-clock and memory marks taken when each pipeline stage begins.
private final class EvaluationStageLog: @unchecked Sendable {
    private let lock = NSLock()
    private let started = Date()
    private var marks: [EvaluationResult.StageMark] = []

    func mark(_ stage: MeetingAnalysisStage) {
        let mark = EvaluationResult.StageMark(
            stage: stage.rawValue,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1_000),
            footprintMB: Int(EvaluationMemory.footprintBytes() / 1_048_576))
        lock.lock()
        marks.append(mark)
        lock.unlock()
    }

    func snapshot() -> [EvaluationResult.StageMark] {
        lock.lock()
        defer { lock.unlock() }
        return marks
    }
}

/// The content of `Documents/Evaluation/<id>/result.json`. Keys are camelCase.
public struct EvaluationResult: Codable, Sendable {
    public struct Turn: Codable, Sendable {
        public let id: String
        public let start: Double
        public let end: Double
        public let speaker: String?
        public let text: String
    }

    public struct Action: Codable, Sendable {
        public let title: String
        public let owner: String?
        public let deadlineText: String?
        public let dueDate: String?
    }

    public struct Timings: Codable, Sendable {
        public let totalMs: Int
        public let transcribeMs: Int
        public let speakersMs: Int
        public let minutesMs: Int
        public let modelLoadMs: Int
        public let modelLoads: Int
        public let chunks: Int
        public let chunkAvgMs: Int
        public let chunkMaxMs: Int
        public let cpuChunks: Int
        public let backgroundRetries: Int
        public let fallbackChunks: Int
        public let thermalWaitMs: Int?
    }

    public struct StageMark: Codable, Sendable {
        public let stage: String
        public let elapsedMs: Int
        public let footprintMB: Int
    }

    public let schema: Int
    public let id: String
    public let commit: String
    public let device: String
    public let osVersion: String
    public let model: String
    public let promptVersion: String
    public let audioSeconds: Double
    public let languageHint: String?
    public let turns: [Turn]
    /// Minutes actions (what the minutes document shows).
    public let tasks: [Action]
    /// Reducer tasks before they are turned into minutes actions.
    public let rawTasks: [Action]
    public let decisions: [String]
    public let openIssues: [String]
    public let summary: String
    public let speakerWarning: String?
    public let timings: Timings
    public let stageMarks: [StageMark]
    public let peakFootprintMB: Int
    public let thermalStateEnd: Int
}

extension MeetingAnalysisPipeline {
    /// A pipeline that keeps every checkpoint under `checkpointRoot` instead of the production
    /// MeetingCheckpoints folder. Used only by the evaluation run.
    public static func makeEvaluationPipeline(checkpointRoot: URL) -> MeetingAnalysisPipeline {
        MeetingAnalysisPipeline(backend: LocalMeetingAnalysisBackend(), checkpointRoot: checkpointRoot)
    }
}

public enum MeetingEvaluation {
    /// Runs transcription, speaker separation and minutes on `audio` and returns everything
    /// the host scorer needs. The checkpoint folder is created and removed inside `scratchRoot`.
    public static func run(id: String, audio: URL, participants: [String], agenda: String?,
                           languageCode: String?, commit: String, device: String,
                           scratchRoot: URL, model: VidurModel = .fast,
                           reviewedTurns: [AnalysisTurn] = [],
                           thermalStatus: @Sendable (Bool) async -> Void = { _ in }) async throws -> EvaluationResult {
        let fileManager = FileManager.default
        let meetingID = UUID()
        let root = scratchRoot.appendingPathComponent("eval-" + meetingID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let pipeline = MeetingAnalysisPipeline.makeEvaluationPipeline(checkpointRoot: root)
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        let meetingDate = Date()
        let zone = TimeZone.current
        let stages = EvaluationStageLog()
        let sampler = EvaluationPeakSampler()
        sampler.start()
        let started = Date()
        var attempts: [AnalysisStageTimings] = []
        var fallbackChunks = 0
        var thermalWaitMs = 0
        let thermalBudgetMs = 600_000
        var result: MeetingAnalysisCheckpoint?
        do {
            while true {
                if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    let clock = ContinuousClock()
                    let waitStarted = clock.now
                    let deadline = waitStarted + .milliseconds(thermalBudgetMs - thermalWaitMs)
                    await thermalStatus(true)
                    while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                        guard clock.now < deadline else { throw OfflineError.thermalPause }
                        try await Task.sleep(for: .seconds(2))
                    }
                    let elapsed = waitStarted.duration(to: clock.now).components
                    thermalWaitMs += Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
                    await thermalStatus(false)
                }
                do {
                    result = try await pipeline.run(
                        meetingID: meetingID, audio: audio, meetingDate: meetingDate, timezone: zone.identifier,
                        languageCode: languageCode, model: model, reviewedTurns: reviewedTurns,
                        participants: participants, agenda: agenda,
                        progress: { stage in stages.mark(stage) })
                    attempts.append(await pipeline.lastStageTimings)
                    fallbackChunks += await pipeline.lastAnalysisFallbackChunks
                    break
                } catch OfflineError.thermalPause {
                    attempts.append(await pipeline.lastStageTimings)
                    fallbackChunks += await pipeline.lastAnalysisFallbackChunks
                    try Task.checkCancellation()
                }
            }
        } catch {
            _ = sampler.stop()
            throw error
        }
        let totalMs = Int(Date().timeIntervalSince(started) * 1_000)
        let peakBytes = sampler.stop()
        guard let checkpoint = result else { throw CancellationError() }
        let chunkTimes = attempts.flatMap(\.chunkMs)
        func sum(_ key: KeyPath<AnalysisStageTimings, Int>) -> Int {
            attempts.reduce(0) { $0 + $1[keyPath: key] }
        }
        let warning = await pipeline.lastSpeakerWarning

        let reduced = MeetingAnalysisReducer.reduce(checkpoint, participants: participants,
                                                    meetingDate: meetingDate, timeZone: zone, agenda: agenda)
        let minutes = reduced.minutes
        let turns = checkpoint.turns.map {
            EvaluationResult.Turn(id: $0.id, start: $0.start, end: $0.end, speaker: $0.speaker, text: $0.text)
        }
        let actions = minutes.actions.map {
            EvaluationResult.Action(title: $0.title, owner: $0.owner, deadlineText: $0.deadlineText, dueDate: $0.dueDate)
        }
        let rawTasks = reduced.tasks.map {
            EvaluationResult.Action(title: $0.title, owner: $0.owner, deadlineText: $0.deadlineText, dueDate: nil)
        }
        let resolutionTexts = minutes.resolutions.map { $0.text }
        let decisions = resolutionTexts.isEmpty ? reduced.decisions.map { $0.text } : resolutionTexts
        let issueTexts = minutes.openIssues.map { $0.text }
        let openIssues = issueTexts.isEmpty ? reduced.openIssues.map { $0.text } : issueTexts
        let overview = minutes.executiveSummary.isEmpty ? reduced.executiveSummary : minutes.executiveSummary
        let chunkAverage = chunkTimes.isEmpty ? 0 : chunkTimes.reduce(0, +) / chunkTimes.count
        return EvaluationResult(
            schema: 1, id: id, commit: commit, device: device,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: model.rawValue, promptVersion: OfflineAnalysisContract.promptVersion,
            audioSeconds: duration.isFinite ? duration : 0, languageHint: languageCode,
            turns: turns, tasks: actions, rawTasks: rawTasks, decisions: decisions, openIssues: openIssues,
            summary: overview, speakerWarning: warning,
            timings: EvaluationResult.Timings(
                totalMs: totalMs, transcribeMs: sum(\.transcriptionMs), speakersMs: sum(\.speakersMs),
                minutesMs: sum(\.minutesMs), modelLoadMs: sum(\.modelLoadMs), modelLoads: sum(\.modelLoads),
                chunks: chunkTimes.count, chunkAvgMs: chunkAverage, chunkMaxMs: chunkTimes.max() ?? 0,
                cpuChunks: sum(\.cpuChunks), backgroundRetries: sum(\.backgroundRetries),
                fallbackChunks: fallbackChunks, thermalWaitMs: thermalWaitMs),
            stageMarks: stages.snapshot(), peakFootprintMB: Int(peakBytes / 1_048_576),
            thermalStateEnd: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
