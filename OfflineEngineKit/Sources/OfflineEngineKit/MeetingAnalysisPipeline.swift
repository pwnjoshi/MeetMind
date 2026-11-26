import Foundation
import AVFoundation
import CryptoKit

public enum VidurModel: String, CaseIterable, Sendable {
    case fast = "qwen-1.7b"
    /// Evaluation-only comparison model. The app never selects it for users.
    case comparison = "qwen-3.5-2b"

    public static let preferenceKey = "Manent.vidurModel"
    /// Model downloads the app no longer offers. `OfflineModelStore` deletes their files once.
    public static let retiredModelIDs = ["qwen-4b"]

    public static var selected: Self {
        migrateSavedSelection()
        return .fast
    }

    /// Any saved selection other than the 1.7B model (the retired 4B or the 2B comparison model)
    /// becomes the 1.7B model.
    public static func migrateSavedSelection(defaults: UserDefaults = .standard) {
        if let saved = defaults.string(forKey: preferenceKey), saved != Self.fast.rawValue {
            defaults.set(Self.fast.rawValue, forKey: preferenceKey)
        }
    }

    public var title: String {
        switch self {
        // Sizes from models.json: 1,282,439,584 bytes (1.7B) and 1,280,835,808 bytes (2B).
        case .fast: return "Qwen3 1.7B \u{00B7} 1.28 GB"
        case .comparison: return "Qwen3.5 2B \u{00B7} 1.28 GB"
        }
    }
}

public enum MeetingAnalysisStage: String, Codable, Sendable {
    case transcription, speakers, analysis, completed
}

public struct TranscriptCorrection: Codable, Sendable {
    public let original: String
    public let alternative: String
    public let replacement: String?
    public let start: Double
    public let end: Double
    public var contextFavorsAlternative: Bool? = nil
}

public struct MeetingAnalysisCheckpoint: Codable, Sendable {
    public let sourceSignature: String
    public var stage: MeetingAnalysisStage
    public var turns: [AnalysisTurn]
    public var speakers: [SpeakerSpan]
    public var analysis: [LocalAnalysisResult]
    public var analyzedChunks: Int
    public var chunkTurnIDs: [[String]]? = nil
    /// Document-grade minutes (topics, resolutions, contextual actions, suggested attendees).
    /// Written by the reducer; absent in checkpoints saved by older versions.
    public var minutes: MinutesContent? = nil
    public var transcriptCorrections: [TranscriptCorrection]? = nil
    public var rankedOverviewFacts: [SupportedPoint]? = nil
    public var draftedOverviewContext: String? = nil
    /// L2-normalised voice embedding per speaker label, from the diarization clustering. Used only to
    /// recognise known voices on this device. Absent in checkpoints saved by older versions.
    public var speakerEmbeddings: [String: [Float]]? = nil
    /// Revision of the diarization model that produced `speakerEmbeddings`. Embeddings from different
    /// revisions are not comparable.
    public var speakerEmbeddingModel: String? = nil

    func excludingUnresolvedCaptions(from turns: [AnalysisTurn]) -> [AnalysisTurn] {
        let unresolved = (transcriptCorrections ?? []).filter { $0.replacement == nil }
        return turns.map { turn in
            guard unresolved.contains(where: {
                $0.start == turn.start && $0.end == turn.end && $0.original.contains(turn.text)
            }) else { return turn }
            return AnalysisTurn(id: turn.id, text: "", start: turn.start, end: turn.end, speaker: turn.speaker)
        }
    }

    public init(sourceSignature: String, stage: MeetingAnalysisStage, turns: [AnalysisTurn],
                speakers: [SpeakerSpan], analysis: [LocalAnalysisResult], analyzedChunks: Int,
                chunkTurnIDs: [[String]]? = nil, minutes: MinutesContent? = nil,
                speakerEmbeddings: [String: [Float]]? = nil, speakerEmbeddingModel: String? = nil) {
        self.sourceSignature = sourceSignature
        self.stage = stage
        self.turns = turns
        self.speakers = speakers
        self.analysis = analysis
        self.analyzedChunks = analyzedChunks
        self.chunkTurnIDs = chunkTurnIDs
        self.minutes = minutes
        self.speakerEmbeddings = speakerEmbeddings
        self.speakerEmbeddingModel = speakerEmbeddingModel
    }
}

/// A local ASR checkpoint produced from a sealed recording window. It contains
/// only text and timing in the protected app container; audio remains in the
/// recording chunk directory. Speaker identity is deliberately finalized over
/// the complete meeting, where cross-window voice clustering is reliable.
struct PreparedRecordingChunk: Codable, Sendable {
    let sequence: Int
    let contentStartTime: TimeInterval
    let endTime: TimeInterval
    let turns: [AnalysisTurn]
    var decodeVersion: String? = nil
}

/// Production orchestration. Downloads are an explicit setup action, never an
/// inference fallback. A checkpoint contains private meeting data and stays in
/// the app's protected, backup-excluded application support directory.
public actor MeetingAnalysisPipeline {
    public static let shared = MeetingAnalysisPipeline()
    private var running = false
    private var activeMeetingID: UUID?
    /// Set when speaker separation fails but transcription can still continue.
    public private(set) var lastSpeakerWarning: String?
    /// Content-free counts from the last final pass: minutes chunks reused from
    /// recording-time pre-analysis versus analyzed after Stop.
    public private(set) var lastAnalysisReuse: (reused: Int, analyzed: Int) = (0, 0)
    /// Chunks whose model output was unusable and fell back to grounded rules.
    public private(set) var lastAnalysisFallbackChunks = 0
    /// Engine-authored error text for the last fallback; never transcript content.
    public private(set) var lastAnalysisFallbackReason: String?
    /// Content-free stage durations from the last run, for the timing log.
    public private(set) var lastStageTimings = AnalysisStageTimings()
    private var preparingChunks = Set<String>()
    private var discardedPreparationMeetingIDs = Set<UUID>()
    private var discardActiveCheckpoint = false
    private let backend: any MeetingAnalysisBackend
    private let checkpointRoot: URL?
    private let resourceGate: @Sendable () -> Bool
    private var preAnalyzing = false
    public static let analysisModelID = VidurModel.fast.rawValue
    public static let requiredModelIDs = ["whisper-large", "diarization", analysisModelID]
    public static let checkpointFormatVersion = "asr-caption-review-v8"
    private static let modelConfiguration = LocalModelConfiguration.compact
    static let analysisChunkBytes = 1800

    /// Extra memory headroom required before the analysis model may load while a
    /// recording is still in progress. Recording audio safety comes first.
    static let preAnalysisExtraReserveBytes: UInt64 = 750_000_000

    public static func defaultResourceGate() -> Bool {
        ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public init() {
        backend = LocalMeetingAnalysisBackend(); checkpointRoot = nil
        resourceGate = { MeetingAnalysisPipeline.defaultResourceGate() }
    }
    init(backend: any MeetingAnalysisBackend, checkpointRoot: URL,
         resourceGate: @escaping @Sendable () -> Bool = { MeetingAnalysisPipeline.defaultResourceGate() }) {
        self.backend = backend; self.checkpointRoot = checkpointRoot; self.resourceGate = resourceGate
    }

    private func checkpointURL(_ id: UUID) throws -> URL {
        let root = try checkpointRoot ?? OfflineModelStore.privateDirectory("MeetingCheckpoints")
        return root.appendingPathComponent(id.uuidString + ".json")
    }

    private func preparationDirectory(meetingID: UUID) throws -> URL {
        // v2: chunks written before the decoder prefill fix are ignored.
        // Those checkpoints could cover a recording with no recognized speech.
        let base = try checkpointRoot?.appendingPathComponent("RecordingChunkPreparation-v2", isDirectory: true)
            ?? OfflineModelStore.privateDirectory("RecordingChunkPreparation-v2")
        return base.appendingPathComponent(meetingID.uuidString, isDirectory: true)
    }

    private func preAnalysisURL(meetingID: UUID) throws -> URL {
        let base = try checkpointRoot?.appendingPathComponent("RecordingPreAnalysis-v1", isDirectory: true)
            ?? OfflineModelStore.privateDirectory("RecordingPreAnalysis-v1")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(meetingID.uuidString + ".json")
    }

    private func loadPreAnalysis(meetingID: UUID, contextKey: String) -> PreAnalysisStore? {
        guard let url = try? preAnalysisURL(meetingID: meetingID),
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(PreAnalysisStore.self, from: data),
              store.contextKey == contextKey else { return nil }
        return store
    }

    private func savePreAnalysis(_ store: PreAnalysisStore, meetingID: UUID) throws {
        try JSONEncoder().encode(store).write(to: try preAnalysisURL(meetingID: meetingID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func removePreAnalysis(meetingID: UUID) {
        if let url = try? preAnalysisURL(meetingID: meetingID), FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func preparationURL(meetingID: UUID, sequence: Int) throws -> URL {
        let root = try preparationDirectory(meetingID: meetingID)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(String(format: "chunk-%04d.json", sequence))
    }

    /// Opportunistically transcribes a closed 30-second recording window while
    /// capture continues. It never downloads models, never blocks recording,
    /// and yields to the full-meeting pipeline. The final pass can reuse a
    /// complete set of these timing-correct checkpoints and only has to run
    /// global diarization plus minute generation.
    @discardableResult
    public func prepareRecordingChunk(meetingID: UUID, sequence: Int, audio: URL,
                                      chunkStartTime: TimeInterval, contentStartTime: TimeInterval,
                                      endTime: TimeInterval, languageCode: String? = nil,
                                      participants: [String] = [], agenda: String? = nil) async throws -> Bool {
        let key = "\(meetingID.uuidString)-\(sequence)"
        guard !running, !preAnalyzing, !preparingChunks.contains(key), resourceGate() else { return false }
        let profiles = try requiredProfiles(model: .fast)
        guard await backend.isInstalled(profiles[0]) else { return false }
        preparingChunks.insert(key)
        defer { preparingChunks.remove(key) }
        let folder = try await backend.verifiedFolder(profiles[0])
        let rawTurns = try await backend.transcribe(audio: audio, folder: folder,
            request: speechRequest(meetingID: meetingID, languageCode: languageCode, participants: participants, agenda: agenda))
        let turns = rawTurns.enumerated().compactMap { index, turn -> AnalysisTurn? in
            let start = turn.start + chunkStartTime
            let end = turn.end + chunkStartTime
            // Discard the five-second duplicated prefix. The adjacent chunk
            // owns that time range, so no repeated sentence reaches minutes.
            guard end > contentStartTime else { return nil }
            return AnalysisTurn(id: "live-\(sequence)-\(index)", text: turn.text,
                                start: max(start, contentStartTime), end: end, speaker: nil)
        }
        guard !turns.isEmpty else { return false }
        if discardedPreparationMeetingIDs.contains(meetingID) { throw CancellationError() }
        let checkpoint = PreparedRecordingChunk(sequence: sequence, contentStartTime: contentStartTime,
                                                endTime: endTime, turns: turns, decodeVersion: Self.checkpointFormatVersion)
        let url = try preparationURL(meetingID: meetingID, sequence: sequence)
        try JSONEncoder().encode(checkpoint).write(to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    private var languageMemories: [UUID: SpeechLanguageMemory] = [:]

    /// One language memory per meeting keeps separately transcribed windows and gaps consistent.
    private func speechRequest(meetingID: UUID, languageCode: String?, participants: [String],
                               agenda: String?) -> SpeechRequest {
        let memory: SpeechLanguageMemory
        if let existing = languageMemories[meetingID] { memory = existing } else {
            memory = SpeechLanguageMemory()
            languageMemories[meetingID] = memory
        }
        return SpeechRequest(languageCode: languageCode,
                             vocabulary: SpeechVocabulary.make(participants: participants, agenda: agenda), memory: memory)
    }

    private func preparedWindows(meetingID: UUID) throws -> [PreparedRecordingChunk] {
        let root = try preparationDirectory(meetingID: meetingID)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var windows: [PreparedRecordingChunk] = []
        for file in files {
            // A window that cannot be decoded is simply a gap that gets retranscribed.
            if let data = try? Data(contentsOf: file),
               let window = try? JSONDecoder().decode(PreparedRecordingChunk.self, from: data),
               window.decodeVersion == Self.checkpointFormatVersion { windows.append(window) }
        }
        return windows.sorted { $0.sequence < $1.sequence }
    }

    /// Reuses prepared windows and transcribes only the time ranges they do not
    /// cover. When too little is prepared, one pass over the whole recording is
    /// cheaper than several model loads and is used instead.
    private func transcribeReusingPreparedWindows(meetingID: UUID, audio: URL, duration: TimeInterval,
                                                  profile: ModelProfile, languageCode: String?,
                                                  participants: [String] = [], agenda: String? = nil) async throws -> [AnalysisTurn] {
        let request = speechRequest(meetingID: meetingID, languageCode: languageCode, participants: participants, agenda: agenda)
        let windows = (try? preparedWindows(meetingID: meetingID)) ?? []
        let plan = RecordingReuse.plan(windows: windows, duration: duration)
        var turns = plan.turns
        var transcribedSeconds = 0.0
        if !plan.gaps.isEmpty {
            let folder = try await backend.verifiedFolder(profile)
            var wholeFile = plan.gaps.count == 1 && plan.gaps[0].start <= 0 && plan.gaps[0].end >= duration
            if !wholeFile {
                var gapTurns: [AnalysisTurn] = []
                for (index, gap) in plan.gaps.enumerated() {
                    try Task.checkCancellation()
                    let clip: URL
                    do { clip = try RecordingReuse.extractAudio(from: audio, start: gap.start, end: gap.end) }
                    catch is CancellationError { throw CancellationError() }
                    catch { wholeFile = true; break }
                    defer { RecordingReuse.removeClip(clip) }
                    let raw = try await backend.transcribe(audio: clip, folder: folder, request: request)
                    gapTurns.append(contentsOf: RecordingReuse.offsetGapTurns(raw, gap: gap, index: index))
                    transcribedSeconds += gap.duration
                }
                if !wholeFile { turns = (turns + gapTurns).sorted { $0.start < $1.start } }
            }
            if wholeFile {
                var recognized = try await backend.transcribe(audio: audio, folder: folder, request: request)
                // A forced language that yields nothing is retried with detection.
                // The recording is unchanged; only the decoder anchor changes.
                if recognized.isEmpty, languageCode != nil {
                    var relaxed = request
                    relaxed.languageCode = nil
                    relaxed.memory = nil
                    recognized = try await backend.transcribe(audio: audio, folder: folder, request: relaxed)
                }
                turns = recognized
                transcribedSeconds = duration
            }
        }
        TranscriptReuseRegistry.shared.record(TranscriptReuseSummary(totalSeconds: duration,
            reusedSeconds: max(0, duration - transcribedSeconds),
            transcribedSeconds: transcribedSeconds), for: meetingID)
        return turns
    }

    /// Match a localized edit using unchanged words from both recognition results.
    static func isCaptionDisagreement(_ original: [String], _ alternate: [String]) -> Bool {
        guard original != alternate, min(original.count, alternate.count) >= 3 else { return false }
        let prefix = zip(original, alternate).prefix(while: { $0.0 == $0.1 }).count
        let suffix = zip(original.dropFirst(prefix).reversed(), alternate.dropFirst(prefix).reversed())
            .prefix(while: { $0.0 == $0.1 }).count
        let shared = prefix + suffix
        let changed = max(original.count, alternate.count) - shared
        return shared >= 3 && changed <= 3 && shared >= changed
    }

    static func isUncoveredCaption(_ caption: AnalysisTurn, in turns: [AnalysisTurn], duration: Double) -> Bool {
        guard caption.start >= 0, caption.end <= duration, caption.end > caption.start,
              caption.end - caption.start <= 6 else { return false }
        return !turns.contains { $0.end > caption.start && $0.start < caption.end }
    }

    /// Recheck a small number of tightly aligned, localized disagreements.
    /// Only the saved audio retry can confirm the alternate wording.
    private func retryCaptionDisagreements(
        turns: [AnalysisTurn], live: [AnalysisTurn], audio: URL, duration: TimeInterval, profile: ModelProfile
    ) async throws -> (turns: [AnalysisTurn], corrections: [TranscriptCorrection]) {
        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: \.isWhitespace).map {
                $0.trimmingCharacters(in: .punctuationCharacters)
            }
        }
        var revised = turns
        var corrections: [TranscriptCorrection] = []
        var attempts = 0
        func confirm(_ alternate: AnalysisTurn, start: Double, end: Double) async throws -> String? {
            let clipStart = max(0, start - 1)
            let clipEnd = min(duration, end + 1)
            do {
                let clip = try RecordingReuse.extractAudio(from: audio, start: clipStart, end: clipEnd)
                defer { RecordingReuse.removeClip(clip) }
                let folder = try await backend.verifiedFolder(profile)
                let retry = try await backend.transcribe(audio: clip, folder: folder,
                    request: SpeechRequest(languageCode: nil, vocabulary: nil, memory: nil))
                let expected = words(alternate.text)
                return retry.first {
                    abs($0.start + clipStart - start) <= 0.75 && abs($0.end + clipStart - end) <= 0.75
                        && words($0.text) == expected
                }?.text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return nil
            }
        }

        // Reserve up to two attempts for phrases entirely absent from the saved transcript.
        var recovered: [AnalysisTurn] = []
        for (index, caption) in live.enumerated() where attempts < 2 {
            try Task.checkCancellation()
            guard Self.isUncoveredCaption(caption, in: revised + recovered, duration: duration),
                  words(caption.text).count >= 3 else { continue }
            attempts += 1
            if let text = try await confirm(caption, start: caption.start, end: caption.end) {
                recovered.append(AnalysisTurn(id: "recovered-live-caption-\(index)", text: text,
                    start: caption.start, end: caption.end, speaker: nil))
            }
        }
        for (index, turn) in turns.enumerated() where attempts < 4 {
            try Task.checkCancellation()
            let original = words(turn.text)
            guard original.count >= 3, turn.end > turn.start, turn.end - turn.start <= 6 else { continue }
            let matching = live.filter { abs($0.start - turn.start) <= 0.75 && abs($0.end - turn.end) <= 0.75 }
            guard matching.count == 1, let alternate = matching.first else { continue }
            guard Self.isCaptionDisagreement(original, words(alternate.text)) else { continue }

            attempts += 1
            var replacement: String?
            defer {
                corrections.append(TranscriptCorrection(original: turn.text, alternative: alternate.text,
                    replacement: replacement, start: turn.start, end: turn.end))
            }
            if let confirmed = try await confirm(alternate, start: turn.start, end: turn.end) {
                replacement = confirmed
                revised[index] = AnalysisTurn(id: turn.id, text: confirmed,
                    start: turn.start, end: turn.end, speaker: turn.speaker)
            }
        }
        return (recovered.isEmpty ? revised : (revised + recovered).sorted { $0.start < $1.start }, corrections)
    }

    /// Analyzes finalized transcript chunks while recording continues, so the
    /// post-recording pass can reuse them. Everything here is optional work:
    /// it does nothing unless the device is cool, not in Low Power Mode, the
    /// analysis model is installed, and memory passes with a generous extra
    /// reserve. It never runs concurrently with Whisper and stops at the first
    /// cancellation check (Stop cancels the calling task). At most `maxChunks`
    /// chunks are analyzed per call so transcription keeps priority.
    @discardableResult
    public func preAnalyzeRecording(meetingID: UUID, meetingDate: Date, timezone: String,
                                    model: VidurModel = .selected, maxChunks: Int = 1) async throws -> Int {
        // A backgrounded recording keeps capturing audio; the language model would have
        // to run on the CPU next to it, so minutes wait for the final pass instead.
        guard !running, !preAnalyzing, preparingChunks.isEmpty, maxChunks > 0, ComputeEnvironment.gpuAvailable,
              !discardedPreparationMeetingIDs.contains(meetingID), resourceGate() else { return 0 }
        let profiles = try requiredProfiles(model: model)
        let profile = profiles[2]
        guard await backend.isInstalled(profile) else { return 0 }
        let configuration = Self.preAnalysisConfiguration
        let contextKey = RecordingReuse.contextKey(profile: profile, configuration: Self.modelConfiguration,
            chunkBytes: Self.analysisChunkBytes, meetingDate: meetingDate, timezone: timezone)
        let prefix = Self.splitTurns(RecordingReuse.contiguousPrefixTurns(try preparedWindows(meetingID: meetingID)))
        guard !prefix.isEmpty else { return 0 }
        var store = loadPreAnalysis(meetingID: meetingID, contextKey: contextKey)
            ?? PreAnalysisStore(contextKey: contextKey, entries: [], checkedChunkCount: 0)
        // A chunk closes after about 1800 bytes of new transcript, so a changed
        // chunk count is the "enough new text" trigger. A chunk is final only once
        // a later chunk exists. This byte plan needs no model, so it is cheap.
        let roughCount = Self.analysisChunks(prefix, maxJSONBytes: Self.analysisChunkBytes).count
        guard roughCount >= 2, roughCount > store.checkedChunkCount else { return 0 }

        preAnalyzing = true
        defer { preAnalyzing = false }
        try Task.checkCancellation()
        let folder = try await backend.verifiedFolder(profile)
        // The final pass may have started while this call was suspended; never
        // hold two language models, and stop at once when Stop cancelled us.
        try Task.checkCancellation()
        guard !running, resourceGate() else { return 0 }
        await backend.releaseSpeechEngine()
        let session: any MeetingAnalysisSession
        do { session = try backend.makeSession(folder: folder, configuration: configuration) }
        catch let error as OfflineError {
            // Not enough headroom while recording is a normal, silent outcome.
            if case .memoryBudget = error { return 0 }
            throw error
        }
        let fitted = try Self.fittedAnalysisChunks(prefix, model: session, meetingDate: meetingDate,
            timezone: timezone, maxJSONBytes: Self.analysisChunkBytes)
        let closed = Array(fitted.dropLast())
        let known = Set(store.entries.map(\.key))
        let pending = closed.filter { !known.contains(RecordingReuse.chunkKey($0)) }
        var analyzed = 0
        for chunk in pending {
            try Task.checkCancellation()
            guard resourceGate(), !discardedPreparationMeetingIDs.contains(meetingID) else { break }
            let result = try session.analyze(turns: chunk, meetingDate: meetingDate, timezone: timezone, question: nil)
            try result.validate(against: chunk)
            store.entries.append(PreAnalysisEntry(key: RecordingReuse.chunkKey(chunk), result: result.sanitized(against: chunk)))
            if discardedPreparationMeetingIDs.contains(meetingID) { throw CancellationError() }
            analyzed += 1
            if analyzed >= pending.count { store.checkedChunkCount = roughCount }
            try savePreAnalysis(store, meetingID: meetingID)
            if analyzed >= maxChunks { break }
        }
        if pending.isEmpty {
            // Nothing new to analyze (or an equivalent chunk is already stored).
            store.checkedChunkCount = roughCount
            try savePreAnalysis(store, meetingID: meetingID)
        }
        return analyzed
    }

    private static var preAnalysisConfiguration: LocalModelConfiguration {
        let base = modelConfiguration
        return LocalModelConfiguration(contextTokens: base.contextTokens, inputTokens: base.inputTokens,
            outputTokens: base.outputTokens, batchTokens: base.batchTokens,
            microBatchTokens: base.microBatchTokens,
            reserveBytes: base.reserveBytes + preAnalysisExtraReserveBytes)
    }
    public func discardCheckpoint(meetingID: UUID) throws {
        if activeMeetingID == meetingID { discardActiveCheckpoint = true }
        let url = try checkpointURL(meetingID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let preparation = try preparationDirectory(meetingID: meetingID)
        if FileManager.default.fileExists(atPath: preparation.path) { try FileManager.default.removeItem(at: preparation) }
        removePreAnalysis(meetingID: meetingID)
        TranscriptReuseRegistry.shared.clear(meetingID: meetingID)
        languageMemories[meetingID] = nil
    }

    /// Signals an active run to cancel and waits briefly for it to relinquish
    /// the meeting before destructive deletion continues.
    public func discardCheckpointAndWait(meetingID: UUID, timeout: TimeInterval = 30) async throws {
        discardedPreparationMeetingIDs.insert(meetingID)
        try discardCheckpoint(meetingID: meetingID)
        let deadline = Date().addingTimeInterval(timeout)
        while activeMeetingID == meetingID || preAnalyzing || preparingChunks.contains(where: { $0.hasPrefix(meetingID.uuidString + "-") }) {
            guard Date() < deadline else {
                throw OfflineError.unavailable("Analysis is still stopping. Retry deletion after processing has stopped.")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        // An in-flight save may have completed while cancellation propagated.
        try discardCheckpoint(meetingID: meetingID)
    }

    public func answer(question: String, turns: [AnalysisTurn], model: VidurModel = .fast) async throws -> [SupportedPoint] {
        guard !running else { throw OfflineError.unavailable("Wait for the current analysis to finish or pause it first.") }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.utf8.count <= 300, !turns.isEmpty else {
            throw OfflineError.unavailable("Ask a short question after a transcript is available.")
        }
        running = true
        defer { running = false }
        try checkConditions()
        guard let profile = try OfflineModelStore.profiles().first(where: { $0.id == model.rawValue }) else {
            throw OfflineError.unavailable("The offline analysis model is unavailable.")
        }
        let folder = try await backend.verifiedFolder(profile)
        await backend.releaseSpeechEngine()
        let model = try backend.makeSession(folder: folder, configuration: Self.modelConfiguration)
        let referenceDate = Date(), timezone = TimeZone.current.identifier
        var points: [SupportedPoint] = []
        var seen = Set<String>()
        let chunks = try Self.fittedAnalysisChunks(turns, model: model, meetingDate: referenceDate,
            timezone: timezone, question: question, maxJSONBytes: 900)
        // Chat should feel immediate. Rank bounded transcript windows by the
        // question vocabulary instead of decoding every historical chunk. The
        // answer remains transcript-grounded; callers can ask a follow-up when
        // no ranked passage supports it.
        let budget = profile.id == VidurModel.comparison.rawValue ? 2 : 3
        for chunk in Self.rankedQuestionChunks(chunks, question: question, limit: budget) {
            try checkConditions()
            let result = try model.analyze(turns: chunk, meetingDate: referenceDate, timezone: timezone, question: question)
            for point in result.discussion where seen.insert(point.text.lowercased()).inserted { points.append(point) }
        }
        return points
    }

    private static func rankedQuestionChunks(_ chunks: [[AnalysisTurn]], question: String, limit: Int) -> [[AnalysisTurn]] {
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count > 2 })
        guard !terms.isEmpty else { return Array(chunks.prefix(limit)) }
        return chunks.enumerated().sorted { lhs, rhs in
            func score(_ chunk: [AnalysisTurn]) -> Int {
                let text = chunk.map(\.text).joined(separator: " ").lowercased()
                return terms.reduce(into: 0) { total, term in if text.contains(term) { total += 1 } }
            }
            let left = score(lhs.element), right = score(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.prefix(limit).map(\.element)
    }

    public func savedCheckpoint(meetingID: UUID) -> MeetingAnalysisCheckpoint? {
        guard let url = try? checkpointURL(meetingID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data)
    }

    public func removeCheckpoint(meetingID: UUID) throws {
        guard !running else { throw OfflineError.unavailable("Wait for the current analysis to finish or pause it first.") }
        let url = try checkpointURL(meetingID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let preparation = try preparationDirectory(meetingID: meetingID)
        if FileManager.default.fileExists(atPath: preparation.path) { try FileManager.default.removeItem(at: preparation) }
        removePreAnalysis(meetingID: meetingID)
        TranscriptReuseRegistry.shared.clear(meetingID: meetingID)
    }

    public func modelReadiness(model: VidurModel = .fast, speakersOnly: Bool = false) async throws -> [(ModelProfile, ModelReadiness)] {
        let profiles = try requiredProfiles(model: model)
        var states: [(ModelProfile, ModelReadiness)] = []
        for profile in profiles.prefix(speakersOnly ? 2 : profiles.count) {
            states.append((profile, await OfflineModelStore.shared.readiness(profile)))
        }
        return states
    }

    public func missingModels(model: VidurModel = .fast, speakersOnly: Bool = false) async throws -> [ModelProfile] {
        try await modelReadiness(model: model, speakersOnly: speakersOnly).compactMap { profile, state in
            state == .ready ? nil : profile
        }
    }

    /// Revision of the installed diarization model. Voice profiles are valid only for one revision.
    public func diarizationModelRevision() -> String? {
        (try? OfflineModelStore.profiles())?.first { $0.id == "diarization" }?.revision
    }

    /// Embeds a short enrolment recording (a person's voice sample) with the diarization embedding
    /// model. Refused while a meeting is being analyzed, so two large models never load at once.
    public func embedVoiceSample(_ audio: URL) async throws -> (embedding: [Float], modelRevision: String)? {
        guard audio.isFileURL else { throw OfflineError.unavailable("Choose a voice sample saved on this iPhone.") }
        guard !running else { return nil }
        running = true
        defer { running = false }
        try checkConditions()
        guard let profile = try OfflineModelStore.profiles().first(where: { $0.id == "diarization" }) else {
            throw OfflineError.unavailable("Required offline model is missing from the manifest.")
        }
        let folder = try await backend.verifiedFolder(profile)
        guard let embedding = try await backend.embedVoiceSample(audio: audio, folder: folder) else { return nil }
        return (embedding, profile.revision)
    }

    public func requiredProfiles(model: VidurModel) throws -> [ModelProfile] {
        let profiles = try OfflineModelStore.profiles()
        return try ["whisper-large", "diarization", model.rawValue].map { id in
            guard let profile = profiles.first(where: { $0.id == id }) else {
                throw OfflineError.unavailable("Required offline model is missing from the manifest.")
            }
            return profile
        }
    }

    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String? = nil,
                    model: VidurModel = .fast,
                    stopAfterSpeakers: Bool = false,
                    reviewedTurns: [AnalysisTurn] = [],
                    participants: [String] = [], agenda: String? = nil,
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        try await run(meetingID: meetingID, audio: audio, meetingDate: meetingDate, timezone: timezone,
                      languageCode: languageCode, model: model, stopAfterSpeakers: stopAfterSpeakers,
                      reviewedTurns: reviewedTurns, participants: participants, agenda: agenda,
                      liveCaptionEvidence: [], progress: progress)
    }

    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String? = nil,
                    model: VidurModel = .fast,
                    stopAfterSpeakers: Bool = false,
                    reviewedTurns: [AnalysisTurn] = [],
                    participants: [String] = [], agenda: String? = nil,
                    liveCaptionEvidence: [AnalysisTurn],
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        guard !running else { throw OfflineError.unavailable("Another meeting is being analyzed. Pause it before starting this one.") }
        running = true
        activeMeetingID = meetingID
        discardActiveCheckpoint = false
        defer { running = false; activeMeetingID = nil; discardActiveCheckpoint = false }
        lastSpeakerWarning = nil
        lastAnalysisReuse = (0, 0)
        lastAnalysisFallbackChunks = 0
        lastAnalysisFallbackReason = nil
        lastStageTimings = AnalysisStageTimings()
        func elapsedMs(_ start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1_000) }
        guard audio.isFileURL else { throw OfflineError.unavailable("Choose a recording saved on this iPhone.") }
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600 else {
            throw OfflineError.unavailable("Offline analysis supports recordings up to 60 minutes. Your audio is preserved.")
        }
        let profiles = try requiredProfiles(model: model)
        let attributes = try FileManager.default.attributesOfItem(atPath: audio.path)
        var signature = "\(audio.lastPathComponent)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date.distantPast)|\(meetingDate.timeIntervalSince1970)|\(timezone)|\(languageCode ?? "auto")|\(profiles.map(\.revision).joined(separator: ","))|\(OfflineAnalysisContract.promptVersion)|\(Self.checkpointFormatVersion)|chunks-v4|ctx\(Self.modelConfiguration.contextTokens)|bytes\(Self.analysisChunkBytes)"
        if !reviewedTurns.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            signature += "|reviewed:\(SHA256.hash(data: try encoder.encode(reviewedTurns)))"
        }
        if !liveCaptionEvidence.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            signature += "|live-evidence:\(SHA256.hash(data: try encoder.encode(liveCaptionEvidence)))"
        }
        let checkpointURL = try self.checkpointURL(meetingID)
        var checkpoint = MeetingAnalysisCheckpoint(sourceSignature: signature,
            stage: reviewedTurns.isEmpty ? .transcription : .analysis,
            turns: reviewedTurns, speakers: [], analysis: [], analyzedChunks: 0)
        if let data = try? Data(contentsOf: checkpointURL),
           let saved = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
           saved.sourceSignature == signature { checkpoint = saved }
        // ASR and diarization run serially. Both engines have high transient
        // memory use, and concurrency is disabled until a separately tested
        // resource governor can admit it for a qualified device profile.
        func save(_ checkpoint: MeetingAnalysisCheckpoint) throws {
            if discardActiveCheckpoint { throw CancellationError() }
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if checkpoint.stage == .transcription {
            try checkConditions()
            await progress(.transcription)
            let started = Date()
            // Windows transcribed during recording are reused; only the time
            // ranges they do not cover are transcribed now.
            checkpoint.turns = Self.splitTurns(try await transcribeReusingPreparedWindows(
                meetingID: meetingID, audio: audio, duration: duration, profile: profiles[0],
                languageCode: languageCode, participants: participants, agenda: agenda))
            if !liveCaptionEvidence.isEmpty {
                let checked = try await retryCaptionDisagreements(
                    turns: checkpoint.turns, live: liveCaptionEvidence, audio: audio,
                    duration: duration, profile: profiles[0])
                checkpoint.turns = checked.turns
                checkpoint.transcriptCorrections = checked.corrections
            }
            lastStageTimings.transcriptionMs = elapsedMs(started)
            await backend.releaseSpeechEngine()
            guard !checkpoint.turns.isEmpty else { throw OfflineError.unavailable("No speech was recognized. Your recording is preserved.") }
            checkpoint.stage = .speakers
            try save(checkpoint)
        }
        if checkpoint.stage == .speakers {
            try checkConditions()
            await progress(.speakers)
            let speakersStarted = Date()
            defer { lastStageTimings.speakersMs = elapsedMs(speakersStarted) }
            await backend.releaseSpeechEngine()
            let rawSpans: [SpeakerSpan]
            var voiceEmbeddings: [String: [Float]] = [:]
            do {
                let folder = try await backend.verifiedFolder(profiles[1])
                // An attendee list does not tell us how many voices are audible.
                let found = try await backend.diarizeWithEmbeddings(audio: audio, folder: folder, expectedSpeakers: nil)
                rawSpans = found.spans
                voiceEmbeddings = found.embeddings
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                rawSpans = []
                lastSpeakerWarning = "Voices could not be separated. Minutes will continue with unnamed speakers."
            }
            checkpoint.speakers = rawSpans.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
            if checkpoint.speakers.isEmpty {
                lastSpeakerWarning = "Voices could not be separated. Minutes will continue with unnamed speakers."
            }
            // Keep embeddings only for voices still present after merging and smoothing.
            let presentLabels = Set(checkpoint.speakers.map(\.speaker))
            let keptEmbeddings = voiceEmbeddings.filter { presentLabels.contains($0.key) }
            checkpoint.speakerEmbeddings = keptEmbeddings.isEmpty ? nil : keptEmbeddings
            checkpoint.speakerEmbeddingModel = keptEmbeddings.isEmpty ? nil : profiles[1].revision
            checkpoint.turns = Self.assignSpeakers(turns: checkpoint.turns, spans: checkpoint.speakers)
            checkpoint.stage = .analysis
            try save(checkpoint)
        }
        if stopAfterSpeakers {
            try Task.checkCancellation()
            if discardActiveCheckpoint { throw CancellationError() }
            return checkpoint
        }
        if checkpoint.stage == .analysis {
            try checkConditions()
            await progress(.analysis)
            let preAnalysisKey = RecordingReuse.contextKey(profile: profiles[2], configuration: Self.modelConfiguration,
                chunkBytes: Self.analysisChunkBytes, meetingDate: meetingDate, timezone: timezone)
            let preAnalyzed: [String: LocalAnalysisResult] = Dictionary(
                (loadPreAnalysis(meetingID: meetingID, contextKey: preAnalysisKey)?.entries ?? []).map { ($0.key, $0.result) },
                uniquingKeysWith: { first, _ in first })
            checkpoint = try await analyzeTranscript(checkpoint, profile: profiles[2],
                meetingDate: meetingDate, timezone: timezone, participants: participants,
                agenda: agenda, preAnalyzed: preAnalyzed, save: save)
            removePreAnalysis(meetingID: meetingID)
        }
        try Task.checkCancellation()
        if discardActiveCheckpoint { throw CancellationError() }
        await progress(.completed)
        return checkpoint
    }

    /// Generate fresh minutes from saved transcript turns without touching recording checkpoints.
    public func reprocessTranscript(meetingID: UUID, turns: [AnalysisTurn], meetingDate: Date, timezone: String,
                                    model: VidurModel, participants: [String], agenda: String?,
                                    corrections: [TranscriptCorrection]? = nil) async throws -> MeetingAnalysisCheckpoint {
        guard !running else { throw OfflineError.unavailable("Another meeting is being analyzed. Try again after it finishes.") }
        guard !turns.isEmpty else { throw OfflineError.unavailable("A saved transcript is required to reprocess minutes.") }
        running = true
        activeMeetingID = meetingID
        discardActiveCheckpoint = false
        defer { running = false; activeMeetingID = nil; discardActiveCheckpoint = false }
        lastAnalysisReuse = (0, 0)
        lastAnalysisFallbackChunks = 0
        lastAnalysisFallbackReason = nil
        lastStageTimings = AnalysisStageTimings()
        try checkConditions()
        let profile = try requiredProfiles(model: model)[2]
        var initial = MeetingAnalysisCheckpoint(sourceSignature: "saved-transcript", stage: .analysis,
            turns: turns, speakers: [], analysis: [], analyzedChunks: 0)
        initial.transcriptCorrections = corrections
        let result = try await analyzeTranscript(initial, profile: profile, meetingDate: meetingDate,
            timezone: timezone, participants: participants, agenda: agenda, preAnalyzed: [:]) { _ in }
        try Task.checkCancellation()
        if discardActiveCheckpoint { throw CancellationError() }
        guard lastAnalysisFallbackChunks == 0 else {
            throw OfflineError.unavailable("The minutes model could not analyze the whole transcript. Please try again.")
        }
        return result
    }

    private func analyzeTranscript(_ initial: MeetingAnalysisCheckpoint, profile: ModelProfile,
                                   meetingDate: Date, timezone: String, participants: [String], agenda: String?,
                                   preAnalyzed: [String: LocalAnalysisResult],
                                   save: (MeetingAnalysisCheckpoint) throws -> Void) async throws -> MeetingAnalysisCheckpoint {
        var checkpoint = initial
        func elapsedMs(_ start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1_000) }
        let minutesStarted = Date()
        defer { lastStageTimings.minutesMs = elapsedMs(minutesStarted) }
        await backend.releaseSpeechEngine()
        let folder = try await backend.verifiedFolder(profile)
        // Optional so the old model is freed before a replacement loads; two
        // resident language models would exceed the memory budget.
        var session: (any MeetingAnalysisSession)?
        func currentSession() throws -> any MeetingAnalysisSession {
            if let session, !ComputeEnvironment.needsReload(session.placement) { return session }
            session = nil
            let loadStarted = Date()
            let loaded = try backend.makeSession(folder: folder, configuration: Self.modelConfiguration)
            lastStageTimings.modelLoadMs += elapsedMs(loadStarted)
            lastStageTimings.modelLoads += 1
            session = loaded
            return loaded
        }
        func analyzeOnce(_ chunk: [AnalysisTurn], placement: inout ComputePlacement) throws -> LocalAnalysisResult {
            let active = try currentSession()
            placement = active.placement
            return try active.analyze(turns: chunk, meetingDate: meetingDate, timezone: timezone,
                question: nil, participants: participants, agenda: agenda)
        }
        /// A chunk interrupted by the move to the background (iOS rejects the GPU
        /// work) is analyzed again on the CPU instead of falling back to rules.
        func analyzeChunk(_ chunk: [AnalysisTurn]) throws -> LocalAnalysisResult {
            var placement = ComputePlacement.independent
            do {
                let result = try analyzeOnce(chunk, placement: &placement)
                if placement == .cpu { lastStageTimings.cpuChunks += 1 }
                return result
            } catch {
                guard !(error is CancellationError), placement == .gpu, !ComputeEnvironment.gpuAvailable else { throw error }
                lastStageTimings.backgroundRetries += 1
                let result = try analyzeOnce(chunk, placement: &placement)
                if placement == .cpu { lastStageTimings.cpuChunks += 1 }
                return result
            }
        }

        if checkpoint.chunkTurnIDs == nil {
            let fitted = try Self.fittedAnalysisChunks(checkpoint.turns, model: try currentSession(),
                meetingDate: meetingDate, timezone: timezone, maxJSONBytes: Self.analysisChunkBytes,
                participants: participants, agenda: agenda)
            var seen = Set<String>()
            checkpoint.turns = fitted.flatMap { $0 }.filter { seen.insert($0.id).inserted }
            checkpoint.chunkTurnIDs = fitted.map { $0.map(\.id) }
            try save(checkpoint)
        }
        guard Set(checkpoint.turns.map(\.id)).count == checkpoint.turns.count else {
            throw OfflineError.unavailable("Transcript checkpoint IDs are invalid. Reanalyze the saved recording.")
        }
        let byID = Dictionary(uniqueKeysWithValues: checkpoint.turns.map { ($0.id, $0) })
        let chunks = try (checkpoint.chunkTurnIDs ?? []).map { ids in
            try ids.map { id in
                guard let turn = byID[id] else {
                    throw OfflineError.unavailable("Analysis checkpoint is invalid. Reanalyze the saved recording.")
                }
                return turn
            }
        }
        guard checkpoint.analyzedChunks == checkpoint.analysis.count,
              checkpoint.analyzedChunks <= chunks.count, !chunks.isEmpty,
              chunks.allSatisfy({ !$0.isEmpty && Set($0.map(\.id)).count == $0.count }),
              Set(chunks.flatMap { $0.map(\.id) }) == Set(checkpoint.turns.map(\.id)) else {
            throw OfflineError.unavailable("Analysis checkpoint is invalid. Preserve the recording and restart analysis.")
        }
        for index in checkpoint.analyzedChunks..<chunks.count {
            try checkConditions()
            if discardActiveCheckpoint { throw CancellationError() }
            let chunk = checkpoint.excludingUnresolvedCaptions(from: chunks[index])
            let result: LocalAnalysisResult
            if chunk.allSatisfy({ $0.text.isEmpty }) {
                result = LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
            } else if let cached = preAnalyzed[RecordingReuse.chunkKey(chunk)],
               (try? cached.validate(against: chunk)) != nil {
                // Identical turn IDs and texts were analyzed during recording.
                result = cached.sanitized(against: chunk)
                lastAnalysisReuse.reused += 1
            } else {
                do {
                    let chunkStarted = Date()
                    let raw = try analyzeChunk(chunk)
                    lastStageTimings.chunkMs.append(elapsedMs(chunkStarted))
                    result = raw.sanitized(against: chunk)
                    lastAnalysisReuse.analyzed += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch OfflineError.thermalPause {
                    throw OfflineError.thermalPause
                } catch OfflineError.memoryBudget(let required, let budget) {
                    throw OfflineError.memoryBudget(requiredEstimate: required, budget: budget)
                } catch {
                    // Unparseable or over-long model output for one chunk. Keep
                    // the meeting going: the reducer's grounded transcript rules
                    // still extract this chunk's explicit actions and decisions.
                    try checkConditions()
                    result = LocalAnalysisResult(discussion: [], decisions: [], tasks: [])
                    lastAnalysisFallbackChunks += 1
                    lastAnalysisFallbackReason = (error as? LocalizedError)?.errorDescription ?? "model output unusable"
                }
            }
            checkpoint.analysis.append(result)
            checkpoint.analyzedChunks = index + 1
            try save(checkpoint)
        }
        if let session, !ComputeEnvironment.needsReload(session.placement),
           var comparisons = checkpoint.transcriptCorrections, !comparisons.isEmpty {
            let contexts = comparisons.map { comparison in
                let before = checkpoint.turns.filter { $0.end <= comparison.start }.suffix(2).map(\.text)
                let after = checkpoint.turns.filter { $0.start >= comparison.end }.prefix(2).map(\.text)
                return [
                    "before": before.map { String($0.prefix(90)) }.joined(separator: " "),
                    "original": String(comparison.original.prefix(180)),
                    "alternative": String(comparison.alternative.prefix(180)),
                    "audio retry": String((comparison.replacement ?? "").prefix(180)),
                    "after": after.map { String($0.prefix(90)) }.joined(separator: " ")
                ]
            }
            do {
                if let selected = try session.reviewCaptionContext(contexts) {
                    let valid = Set(selected.filter { comparisons.indices.contains($0) })
                    for index in comparisons.indices {
                        comparisons[index].contextFavorsAlternative = valid.contains(index) ? true : nil
                    }
                    checkpoint.transcriptCorrections = comparisons
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }
        }
        if let session, !ComputeEnvironment.needsReload(session.placement) {
            let reduced = MeetingAnalysisReducer.reduce(checkpoint, participants: participants,
                meetingDate: meetingDate, timeZone: TimeZone(identifier: timezone) ?? .current, agenda: agenda)
            let overviewTurns = checkpoint.excludingUnresolvedCaptions(from: checkpoint.turns)
            let overviewNames = MinutesBuilder.overviewNames(turns: overviewTurns, participants: participants,
                                                             speakerNames: [:], tasks: reduced.tasks)
            // The model only ranks and lightly edits sentences that already pass the overview rules.
            let facts = Array(reduced.discussion.filter {
                MinutesBuilder.isUsableOverviewSentence($0.text, turns: overviewTurns, names: overviewNames)
                    && !$0.evidence.isEmpty && $0.text.utf8.count <= 240
            }.prefix(10))
            if !facts.isEmpty {
                do {
                    let context = overviewTurns
                    if let draft = try session.draftOverviewContext(facts, transcript: context),
                       facts.indices.contains(draft.index) {
                        checkpoint.rankedOverviewFacts = [facts[draft.index]]
                        checkpoint.draftedOverviewContext = draft.text
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                }
            }
        }
        checkpoint.stage = .completed
        try save(checkpoint)
        return checkpoint
    }

    /// Use the actual model tokenizer, including instructions and question, to
    /// fit inputs without discarding any transcript text. Plans are checkpointed
    /// so a resumed run cannot skip different chunks after finer splitting.
    static func fittedAnalysisChunks(_ turns: [AnalysisTurn], model: any MeetingAnalysisSession,
        meetingDate: Date, timezone: String, question: String? = nil, maxJSONBytes: Int = 1200,
        participants: [String] = [], agenda: String? = nil) throws -> [[AnalysisTurn]] {
        var fitted: [[AnalysisTurn]] = [], seen = Set<[String]>()
        func fit(_ chunk: [AnalysisTurn]) throws {
            try Task.checkCancellation()
            guard !chunk.isEmpty else { return }
            if try model.inputTokenCount(turns: chunk, meetingDate: meetingDate, timezone: timezone, question: question,
                                         participants: participants, agenda: agenda) <= model.inputTokenLimit {
                if seen.insert(chunk.map(\.id)).inserted { fitted.append(chunk) }
            } else if chunk.count > 1 {
                let middle = chunk.count / 2
                try fit(Array(chunk[..<middle]))
                try fit(Array(chunk[middle...]))
            } else {
                let turn = chunk[0], characters = Array(chunk[0].text)
                guard characters.count > 1 else {
                    throw OfflineError.unavailable("The model context cannot fit this input. Shorten the question or restart analysis.")
                }
                let middle = characters.count / 2
                try fit([AnalysisTurn(id: turn.id + ".0", text: String(characters[..<middle]), start: turn.start, end: turn.end, speaker: turn.speaker)])
                try fit([AnalysisTurn(id: turn.id + ".1", text: String(characters[middle...]), start: turn.start, end: turn.end, speaker: turn.speaker)])
            }
        }
        for chunk in analysisChunks(turns, maxJSONBytes: maxJSONBytes) { try fit(chunk) }
        return fitted
    }

    private func checkConditions() throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            throw OfflineError.thermalPause
        }
    }

    // Never equate a diarized voice label with a named attendee. Ambiguous or
    // overlapping speech remains unassigned rather than guessing an owner.
    static func assignSpeakers(turns: [AnalysisTurn], spans: [SpeakerSpan]) -> [AnalysisTurn] {
        let assigned = turns.map { turn in
            var overlap: [String: Double] = [:]
            for span in spans {
                overlap[span.speaker, default: 0] += max(0, min(turn.end, span.end) - max(turn.start, span.start))
            }
            let ranked = overlap.sorted { $0.value > $1.value }
            let duration = max(0, turn.end - turn.start)
            let winner = ranked.first
            let label = duration > 0 && (winner?.value ?? 0) >= duration * 0.6
                && (ranked.dropFirst().first?.value ?? 0) < duration * 0.2 ? winner?.key : nil
            return AnalysisTurn(id: turn.id, text: turn.text, start: turn.start, end: turn.end, speaker: label)
        }
        return assigned.enumerated().map { index, turn in
            guard index > 0, let label = turn.speaker else { return turn }
            let question = assigned[index - 1]
            let gap = turn.start - question.end
            guard question.speaker == label, (-0.3...1.2).contains(gap),
                  question.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?"),
                  MinutesRegex.firstMatch(#"^[\p{Lu}][\p{L}'-]+,\s*(?i:(?:can|could|would|will)\s+you\b)"#,
                                          in: question.text) != nil,
                  MinutesRegex.firstMatch(#"(?i)^\s*(?:yes|yeah|yep|sure|no|nope)\b"#, in: turn.text) != nil
            else { return turn }
            // An answer addressed to someone else may cross a diarization boundary.
            // Leave it unnamed until there is evidence for a different voice.
            return AnalysisTurn(id: turn.id, text: turn.text, start: turn.start, end: turn.end, speaker: nil)
        }
    }

    /// Bounded Unicode-safe fragments keep even a long uninterrupted speaker
    /// turn within the model's input budget. Evidence IDs survive checkpointing.
    private static func splitTurns(_ turns: [AnalysisTurn]) -> [AnalysisTurn] {
        var fragments: [AnalysisTurn] = []
        for turn in turns {
            guard !turn.text.isEmpty else { continue }
            if turn.text.utf8.count <= 600 { fragments.append(turn); continue }
            var parts: [String] = [], part = "", bytes = 0
            for character in turn.text {
                let next = String(character)
                if bytes + next.utf8.count > 600 && !part.isEmpty {
                    parts.append(part); part = ""; bytes = 0
                }
                part += next; bytes += next.utf8.count
            }
            if !part.isEmpty { parts.append(part) }
            for (index, text) in parts.enumerated() {
                fragments.append(AnalysisTurn(id: "\(turn.id).\(index)", text: text,
                    start: turn.start, end: turn.end, speaker: turn.speaker))
            }
        }
        return fragments
    }

    static func analysisChunks(_ turns: [AnalysisTurn], maxJSONBytes: Int = 1800) -> [[AnalysisTurn]] {
        let fragments = splitTurns(turns)
        let encoder = JSONEncoder()
        func inputBytes(_ values: [AnalysisTurn]) -> Int {
            // Speaker labels are unknown while recording and present afterwards.
            // Budgeting with a fixed label keeps the plan identical in both cases,
            // so chunks analyzed during recording can be reused.
            let budgeted = values.map {
                AnalysisTurn(id: $0.id, text: $0.text, start: $0.start, end: $0.end, speaker: "Speaker 1")
            }
            return (try? encoder.encode(budgeted).count) ?? Int.max
        }
        var result: [[AnalysisTurn]] = [], chunk: [AnalysisTurn] = []
        for turn in fragments {
            if inputBytes(chunk + [turn]) > maxJSONBytes && !chunk.isEmpty {
                result.append(chunk)
                chunk = Array(chunk.suffix(1))
                if inputBytes(chunk + [turn]) > maxJSONBytes { chunk = [] }
            }
            chunk.append(turn)
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
