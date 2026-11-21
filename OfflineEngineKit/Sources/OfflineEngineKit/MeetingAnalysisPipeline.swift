import Foundation
import AVFoundation
import CryptoKit

public enum VidurModel: String, CaseIterable, Sendable {
    case fast = "qwen-1.7b"
    case large = "qwen-4b"

    public static let preferenceKey = "Manent.vidurModel"
    public static var selected: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .fast
    }

    public var title: String {
        switch self {
        case .fast: return "Qwen3 1.7B · 1.28 GB"
        case .large: return "Qwen3 4B · 2.50 GB"
        }
    }
}

public enum MeetingAnalysisStage: String, Codable, Sendable {
    case transcription, speakers, analysis, completed
}

public struct MeetingAnalysisCheckpoint: Codable, Sendable {
    public let sourceSignature: String
    public var stage: MeetingAnalysisStage
    public var turns: [AnalysisTurn]
    public var speakers: [SpeakerSpan]
    public var analysis: [LocalAnalysisResult]
    public var analyzedChunks: Int
    public var chunkTurnIDs: [[String]]? = nil

    public init(sourceSignature: String, stage: MeetingAnalysisStage, turns: [AnalysisTurn],
                speakers: [SpeakerSpan], analysis: [LocalAnalysisResult], analyzedChunks: Int,
                chunkTurnIDs: [[String]]? = nil) {
        self.sourceSignature = sourceSignature
        self.stage = stage
        self.turns = turns
        self.speakers = speakers
        self.analysis = analysis
        self.analyzedChunks = analyzedChunks
        self.chunkTurnIDs = chunkTurnIDs
    }
}

/// A local ASR checkpoint produced from a sealed recording window. It contains
/// only text and timing in the protected app container; audio remains in the
/// recording chunk directory. Speaker identity is deliberately finalized over
/// the complete meeting, where cross-window voice clustering is reliable.
private struct PreparedRecordingChunk: Codable, Sendable {
    let sequence: Int
    let contentStartTime: TimeInterval
    let endTime: TimeInterval
    let turns: [AnalysisTurn]
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
    private var preparingChunks = Set<String>()
    private var discardedPreparationMeetingIDs = Set<UUID>()
    private var discardActiveCheckpoint = false
    private let backend: any MeetingAnalysisBackend
    private let checkpointRoot: URL?
    public static let analysisModelID = "qwen-4b"
    public static let requiredModelIDs = ["whisper-large", "diarization", analysisModelID]
    public static let checkpointFormatVersion = "asr-prefill-v2"
    private static let modelConfiguration = LocalModelConfiguration.compact
    static let analysisChunkBytes = 1800
    public init() { backend = LocalMeetingAnalysisBackend(); checkpointRoot = nil }
    init(backend: any MeetingAnalysisBackend, checkpointRoot: URL) {
        self.backend = backend; self.checkpointRoot = checkpointRoot
    }

    private func checkpointURL(_ id: UUID) throws -> URL {
        let root = try checkpointRoot ?? OfflineModelStore.privateDirectory("MeetingCheckpoints")
        return root.appendingPathComponent(id.uuidString + ".json")
    }

    private func preparationDirectory(meetingID: UUID) throws -> URL {
        // v2: chunks written before the decoder prefill fix are ignored.
        // Those checkpoints could cover a recording with no recognized speech.
        try OfflineModelStore.privateDirectory("RecordingChunkPreparation-v2")
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
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
                                      endTime: TimeInterval, languageCode: String? = nil) async throws -> Bool {
        let key = "\(meetingID.uuidString)-\(sequence)"
        guard !running, !preparingChunks.contains(key),
              ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }
        let profiles = try requiredProfiles(model: .fast)
        guard await OfflineModelStore.shared.isInstalled(profiles[0]) else { return false }
        preparingChunks.insert(key)
        defer { preparingChunks.remove(key) }
        let folder = try await backend.verifiedFolder(profiles[0])
        let rawTurns = try await backend.transcribe(audio: audio, folder: folder, languageCode: languageCode)
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
                                                endTime: endTime, turns: turns)
        let url = try preparationURL(meetingID: meetingID, sequence: sequence)
        try JSONEncoder().encode(checkpoint).write(to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    private func preparedTurns(meetingID: UUID, duration: TimeInterval) throws -> [AnalysisTurn]? {
        let root = try preparationDirectory(meetingID: meetingID)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let windows = try files.map { try JSONDecoder().decode(PreparedRecordingChunk.self, from: Data(contentsOf: $0)) }
            .sorted { $0.sequence < $1.sequence }
        guard let first = windows.first, let last = windows.last,
              first.contentStartTime <= 0.5, last.endTime >= duration - 0.5 else { return nil }
        var coveredEnd = first.contentStartTime
        for window in windows {
            guard window.contentStartTime <= coveredEnd + 0.75 else { return nil }
            coveredEnd = max(coveredEnd, window.endTime)
        }
        var seen = Set<String>()
        return windows.flatMap(\.turns).sorted { $0.start < $1.start }.filter { turn in
            let key = "\(Int(turn.start * 10))|\(turn.text.lowercased())"
            return seen.insert(key).inserted
        }
    }

    public func discardCheckpoint(meetingID: UUID) throws {
        if activeMeetingID == meetingID { discardActiveCheckpoint = true }
        let url = try checkpointURL(meetingID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let preparation = try preparationDirectory(meetingID: meetingID)
        if FileManager.default.fileExists(atPath: preparation.path) { try FileManager.default.removeItem(at: preparation) }
    }

    /// Signals an active run to cancel and waits briefly for it to relinquish
    /// the meeting before destructive deletion continues.
    public func discardCheckpointAndWait(meetingID: UUID, timeout: TimeInterval = 30) async throws {
        discardedPreparationMeetingIDs.insert(meetingID)
        try discardCheckpoint(meetingID: meetingID)
        let deadline = Date().addingTimeInterval(timeout)
        while activeMeetingID == meetingID || preparingChunks.contains(where: { $0.hasPrefix(meetingID.uuidString + "-") }) {
            guard Date() < deadline else {
                throw OfflineError.unavailable("Analysis is still stopping. Retry deletion after processing has stopped.")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        // An in-flight save may have completed while cancellation propagated.
        try discardCheckpoint(meetingID: meetingID)
    }

    public func answer(question: String, turns: [AnalysisTurn], model: VidurModel = .large) async throws -> [SupportedPoint] {
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
        let budget = profile.id == VidurModel.fast.rawValue ? 2 : 3
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
    }

    public func modelReadiness(model: VidurModel = .large, speakersOnly: Bool = false) async throws -> [(ModelProfile, ModelReadiness)] {
        let profiles = try requiredProfiles(model: model)
        var states: [(ModelProfile, ModelReadiness)] = []
        for profile in profiles.prefix(speakersOnly ? 2 : profiles.count) {
            states.append((profile, await OfflineModelStore.shared.readiness(profile)))
        }
        return states
    }

    public func missingModels(model: VidurModel = .large, speakersOnly: Bool = false) async throws -> [ModelProfile] {
        try await modelReadiness(model: model, speakersOnly: speakersOnly).compactMap { profile, state in
            state == .ready ? nil : profile
        }
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
                    model: VidurModel = .large,
                    stopAfterSpeakers: Bool = false,
                    reviewedTurns: [AnalysisTurn] = [],
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        guard !running else { throw OfflineError.unavailable("Another meeting is being analyzed. Pause it before starting this one.") }
        running = true
        activeMeetingID = meetingID
        discardActiveCheckpoint = false
        defer { running = false; activeMeetingID = nil; discardActiveCheckpoint = false }
        lastSpeakerWarning = nil
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
        func save() throws {
            if discardActiveCheckpoint { throw CancellationError() }
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if checkpoint.stage == .transcription {
            try checkConditions()
            await progress(.transcription)
            if let prepared = try preparedTurns(meetingID: meetingID, duration: duration), !prepared.isEmpty {
                checkpoint.turns = Self.splitTurns(prepared)
            } else {
                let transcriptionFolder = try await backend.verifiedFolder(profiles[0])
                var recognized = Self.splitTurns(try await backend.transcribe(
                    audio: audio, folder: transcriptionFolder, languageCode: languageCode))
                // A forced language that yields nothing is retried with detection.
                // The recording is unchanged; only the decoder anchor changes.
                if recognized.isEmpty, languageCode != nil {
                    recognized = Self.splitTurns(try await backend.transcribe(
                        audio: audio, folder: transcriptionFolder, languageCode: nil))
                }
                checkpoint.turns = recognized
            }
            guard !checkpoint.turns.isEmpty else { throw OfflineError.unavailable("No speech was recognized. Your recording is preserved.") }
            checkpoint.stage = .speakers
            try save()
        }
        if checkpoint.stage == .speakers {
            try checkConditions()
            await progress(.speakers)
            let rawSpans: [SpeakerSpan]
            do {
                let folder = try await backend.verifiedFolder(profiles[1])
                rawSpans = try await backend.diarize(audio: audio, folder: folder)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                rawSpans = []
                lastSpeakerWarning = "Voices could not be separated. Minutes will continue with unnamed speakers."
            }
            checkpoint.speakers = Self.stabilizeSpeakerSpans(rawSpans)
            checkpoint.turns = Self.assignSpeakers(turns: checkpoint.turns, spans: checkpoint.speakers)
            checkpoint.stage = .analysis
            try save()
        }
        if stopAfterSpeakers {
            try Task.checkCancellation()
            if discardActiveCheckpoint { throw CancellationError() }
            return checkpoint
        }
        if checkpoint.stage == .analysis {
            try checkConditions()
            await progress(.analysis)
            let folder = try await backend.verifiedFolder(profiles[2])
            let model = try backend.makeSession(folder: folder, configuration: Self.modelConfiguration)
            if checkpoint.chunkTurnIDs == nil {
                let fitted = try Self.fittedAnalysisChunks(checkpoint.turns, model: model,
                    meetingDate: meetingDate, timezone: timezone, maxJSONBytes: Self.analysisChunkBytes)
                var seen = Set<String>()
                checkpoint.turns = fitted.flatMap { $0 }.filter { seen.insert($0.id).inserted }
                checkpoint.chunkTurnIDs = fitted.map { $0.map(\.id) }
                try save()
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
                let result = try model.analyze(turns: chunks[index], meetingDate: meetingDate, timezone: timezone, question: nil)
                try result.validate(against: chunks[index])
                checkpoint.analysis.append(result)
                checkpoint.analyzedChunks = index + 1
                try save()
            }
            checkpoint.stage = .completed
            try save()
        }
        try Task.checkCancellation()
        if discardActiveCheckpoint { throw CancellationError() }
        await progress(.completed)
        return checkpoint
    }

    /// Use the actual model tokenizer, including instructions and question, to
    /// fit inputs without discarding any transcript text. Plans are checkpointed
    /// so a resumed run cannot skip different chunks after finer splitting.
    static func fittedAnalysisChunks(_ turns: [AnalysisTurn], model: any MeetingAnalysisSession,
        meetingDate: Date, timezone: String, question: String? = nil, maxJSONBytes: Int = 1200) throws -> [[AnalysisTurn]] {
        var fitted: [[AnalysisTurn]] = [], seen = Set<[String]>()
        func fit(_ chunk: [AnalysisTurn]) throws {
            try Task.checkCancellation()
            guard !chunk.isEmpty else { return }
            if try model.inputTokenCount(turns: chunk, meetingDate: meetingDate, timezone: timezone, question: question) <= model.inputTokenLimit {
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
            throw OfflineError.unavailable("iPhone is too warm. Let it cool down, then resume analysis.")
        }
    }

    // Never equate a diarized voice label with a named attendee. Ambiguous or
    // overlapping speech remains unassigned rather than guessing an owner.
    static func assignSpeakers(turns: [AnalysisTurn], spans: [SpeakerSpan]) -> [AnalysisTurn] {
        turns.map { turn in
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
    }

    /// Keep a transient clustering glitch from presenting one person as several
    /// named speakers. We only smooth extremely short label flips and collapse a
    /// clearly dominant voice; ambiguous multi-person recordings remain reviewable.
    static func stabilizeSpeakerSpans(_ spans: [SpeakerSpan]) -> [SpeakerSpan] {
        let ordered = spans.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }
        var stabilized = ordered
        if stabilized.count >= 3 {
            for index in 1..<(stabilized.count - 1) {
                let previous = stabilized[index - 1]
                let current = stabilized[index]
                let next = stabilized[index + 1]
                if current.end - current.start < 1.5, previous.speaker == next.speaker,
                   previous.end <= current.start + 0.5, current.end <= next.start + 0.5 {
                    stabilized[index] = SpeakerSpan(speaker: previous.speaker, start: current.start, end: current.end)
                }
            }
        }
        let totals = stabilized.reduce(into: [String: Double]()) { result, span in
            result[span.speaker, default: 0] += span.end - span.start
        }
        let totalSpeech = totals.values.reduce(0, +)
        guard totalSpeech > 0, let dominant = totals.max(by: { $0.value < $1.value }) else { return stabilized }
        // A label covering at least 88% of speech is safer to render as one voice
        // than to expose short false-positive labels from overlap/noise.
        guard dominant.value / totalSpeech >= 0.88 else { return stabilized }
        return stabilized.map { SpeakerSpan(speaker: dominant.key, start: $0.start, end: $0.end) }
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
            (try? encoder.encode(values).count) ?? Int.max
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
