import Foundation
import AVFoundation

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
}

/// Production orchestration. Downloads are an explicit setup action, never an
/// inference fallback. A checkpoint contains private meeting data and stays in
/// the app's protected, backup-excluded application support directory.
public actor MeetingAnalysisPipeline {
    public static let shared = MeetingAnalysisPipeline()
    private var running = false
    private var activeMeetingID: UUID?
    private var discardActiveCheckpoint = false
    private let backend: any MeetingAnalysisBackend
    private let checkpointRoot: URL?
    public static let analysisModelID = "qwen-4b"
    public static let requiredModelIDs = ["whisper-large", "diarization", analysisModelID]
    private static let modelConfiguration = LocalModelConfiguration.compact
    private static let analysisChunkBytes = 1200
    public init() { backend = LocalMeetingAnalysisBackend(); checkpointRoot = nil }
    init(backend: any MeetingAnalysisBackend, checkpointRoot: URL) {
        self.backend = backend; self.checkpointRoot = checkpointRoot
    }

    private func checkpointURL(_ id: UUID) throws -> URL {
        let root = try checkpointRoot ?? OfflineModelStore.privateDirectory("MeetingCheckpoints")
        return root.appendingPathComponent(id.uuidString + ".json")
    }

    public func discardCheckpoint(meetingID: UUID) throws {
        if activeMeetingID == meetingID { discardActiveCheckpoint = true }
        let url = try checkpointURL(meetingID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func answer(question: String, turns: [AnalysisTurn]) async throws -> [SupportedPoint] {
        guard !running else { throw OfflineError.unavailable("Wait for the current analysis to finish or pause it first.") }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.utf8.count <= 300, !turns.isEmpty else {
            throw OfflineError.unavailable("Ask a short question after a transcript is available.")
        }
        running = true
        defer { running = false }
        try checkConditions()
        guard let profile = try OfflineModelStore.profiles().first(where: { $0.id == Self.analysisModelID }) else {
            throw OfflineError.unavailable("The offline analysis model is unavailable.")
        }
        let folder = try await backend.verifiedFolder(profile)
        let model = try backend.makeSession(folder: folder, configuration: Self.modelConfiguration)
        let referenceDate = Date(), timezone = TimeZone.current.identifier
        var points: [SupportedPoint] = []
        var seen = Set<String>()
        for chunk in try Self.fittedAnalysisChunks(turns, model: model, meetingDate: referenceDate,
            timezone: timezone, question: question, maxJSONBytes: 900) {
            try checkConditions()
            let result = try model.analyze(turns: chunk, meetingDate: referenceDate, timezone: timezone, question: question)
            for point in result.discussion where seen.insert(point.text.lowercased()).inserted { points.append(point) }
        }
        return points
    }

    public func removeCheckpoint(meetingID: UUID) throws {
        guard !running else { throw OfflineError.unavailable("Wait for the current analysis to finish or pause it first.") }
        let url = try checkpointURL(meetingID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func missingModels() async throws -> [ModelProfile] {
        var missing: [ModelProfile] = []
        for profile in try requiredProfiles() {
            if !(await OfflineModelStore.shared.isInstalled(profile)) { missing.append(profile) }
        }
        return missing
    }

    private func requiredProfiles() throws -> [ModelProfile] {
        let profiles = try OfflineModelStore.profiles()
        return try Self.requiredModelIDs.map { id in
            guard let profile = profiles.first(where: { $0.id == id }) else {
                throw OfflineError.unavailable("Required offline model is missing from the manifest.")
            }
            return profile
        }
    }

    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String, languageCode: String? = nil,
                    progress: @Sendable (MeetingAnalysisStage) async -> Void) async throws -> MeetingAnalysisCheckpoint {
        guard !running else { throw OfflineError.unavailable("Another meeting is being analyzed. Pause it before starting this one.") }
        running = true
        activeMeetingID = meetingID
        discardActiveCheckpoint = false
        defer { running = false; activeMeetingID = nil; discardActiveCheckpoint = false }
        guard audio.isFileURL else { throw OfflineError.unavailable("Choose a recording saved on this iPhone.") }
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600 else {
            throw OfflineError.unavailable("Offline analysis supports recordings up to 60 minutes. Your audio is preserved.")
        }
        let profiles = try requiredProfiles()
        // Verify all dependencies before modifying any saved result.
        var folders: [URL] = []
        for profile in profiles { folders.append(try await backend.verifiedFolder(profile)) }
        let attributes = try FileManager.default.attributesOfItem(atPath: audio.path)
        let signature = "\(audio.lastPathComponent)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date.distantPast)|\(meetingDate.timeIntervalSince1970)|\(timezone)|\(languageCode ?? "auto")|\(profiles.map(\.revision).joined(separator: ","))|\(OfflineAnalysisContract.promptVersion)|chunks-v4|ctx\(Self.modelConfiguration.contextTokens)|bytes\(Self.analysisChunkBytes)"
        let checkpointURL = try self.checkpointURL(meetingID)
        var checkpoint = MeetingAnalysisCheckpoint(sourceSignature: signature, stage: .transcription,
            turns: [], speakers: [], analysis: [], analyzedChunks: 0)
        if let data = try? Data(contentsOf: checkpointURL),
           let saved = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
           saved.sourceSignature == signature { checkpoint = saved }
        // ASR and diarization consume the same finished audio but have no data
        // dependency. On a cool, normally-powered device we start diarization
        // while transcription is running, then retain the normal checkpoint
        // boundary after transcription. This shortens finalization without
        // sacrificing resumability or competing when the phone is constrained.
        var overlappingDiarization: Task<[SpeakerSpan], Error>?
        defer { overlappingDiarization?.cancel() }
        func save() throws {
            if discardActiveCheckpoint { throw CancellationError() }
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if checkpoint.stage == .transcription {
            try checkConditions()
            await progress(.transcription)
            if ProcessInfo.processInfo.thermalState == .nominal,
               !ProcessInfo.processInfo.isLowPowerModeEnabled {
                let backend = self.backend
                let diarizationFolder = folders[1]
                overlappingDiarization = Task {
                    try await backend.diarize(audio: audio, folder: diarizationFolder)
                }
            }
            checkpoint.turns = Self.splitTurns(try await backend.transcribe(audio: audio, folder: folders[0], languageCode: languageCode))
            guard !checkpoint.turns.isEmpty else { throw OfflineError.unavailable("No speech was recognized. Your recording is preserved.") }
            checkpoint.stage = .speakers
            try save()
        }
        if checkpoint.stage == .speakers {
            try checkConditions()
            await progress(.speakers)
            let rawSpans: [SpeakerSpan]
            if let overlappingDiarization {
                rawSpans = try await overlappingDiarization.value
            } else {
                rawSpans = try await backend.diarize(audio: audio, folder: folders[1])
            }
            checkpoint.speakers = Self.stabilizeSpeakerSpans(rawSpans)
            checkpoint.turns = Self.assignSpeakers(turns: checkpoint.turns, spans: checkpoint.speakers)
            checkpoint.stage = .analysis
            try save()
        }
        if checkpoint.stage == .analysis {
            try checkConditions()
            await progress(.analysis)
            let model = try backend.makeSession(folder: folders[2], configuration: Self.modelConfiguration)
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
