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
    public static let requiredModelIDs = ["whisper-large", "diarization", "qwen-1.7b"]
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
        guard let profile = try OfflineModelStore.profiles().first(where: { $0.id == "qwen-1.7b" }) else {
            throw OfflineError.unavailable("The offline analysis model is unavailable.")
        }
        let folder = try await backend.verifiedFolder(profile)
        let model = try backend.makeSession(folder: folder)
        var points: [SupportedPoint] = []
        var seen = Set<String>()
        for chunk in Self.analysisChunks(turns) {
            try checkConditions()
            let result = try model.analyze(turns: chunk, meetingDate: Date(), timezone: TimeZone.current.identifier, question: question)
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

    public func run(meetingID: UUID, audio: URL, meetingDate: Date, timezone: String,
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
        let signature = "\(audio.lastPathComponent)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date.distantPast)|\(meetingDate.timeIntervalSince1970)|\(timezone)|\(profiles.map(\.revision).joined(separator: ","))|v2"
        let checkpointURL = try self.checkpointURL(meetingID)
        var checkpoint = MeetingAnalysisCheckpoint(sourceSignature: signature, stage: .transcription,
            turns: [], speakers: [], analysis: [], analyzedChunks: 0)
        if let data = try? Data(contentsOf: checkpointURL),
           let saved = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
           saved.sourceSignature == signature { checkpoint = saved }
        func save() throws {
            if discardActiveCheckpoint { throw CancellationError() }
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if checkpoint.stage == .transcription {
            try checkConditions()
            await progress(.transcription)
            checkpoint.turns = Self.splitTurns(try await backend.transcribe(audio: audio, folder: folders[0]))
            guard !checkpoint.turns.isEmpty else { throw OfflineError.unavailable("No speech was recognized. Your recording is preserved.") }
            checkpoint.stage = .speakers
            try save()
        }
        if checkpoint.stage == .speakers {
            try checkConditions()
            await progress(.speakers)
            checkpoint.speakers = try await backend.diarize(audio: audio, folder: folders[1])
            checkpoint.turns = Self.assignSpeakers(turns: checkpoint.turns, spans: checkpoint.speakers)
            checkpoint.stage = .analysis
            try save()
        }
        if checkpoint.stage == .analysis {
            try checkConditions()
            await progress(.analysis)
            let chunks = Self.analysisChunks(checkpoint.turns)
            guard checkpoint.analyzedChunks == checkpoint.analysis.count,
                  checkpoint.analyzedChunks <= chunks.count else {
                throw OfflineError.unavailable("Analysis checkpoint is invalid. Preserve the recording and restart analysis.")
            }
            let model = try backend.makeSession(folder: folders[2])
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

    static func analysisChunks(_ turns: [AnalysisTurn]) -> [[AnalysisTurn]] {
        let fragments = splitTurns(turns)
        let encoder = JSONEncoder()
        func inputBytes(_ values: [AnalysisTurn]) -> Int {
            (try? encoder.encode(values).count) ?? Int.max
        }
        var result: [[AnalysisTurn]] = [], chunk: [AnalysisTurn] = []
        for turn in fragments {
            if inputBytes(chunk + [turn]) > 1800 && !chunk.isEmpty {
                result.append(chunk)
                chunk = Array(chunk.suffix(1))
                if inputBytes(chunk + [turn]) > 1800 { chunk = [] }
            }
            chunk.append(turn)
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
