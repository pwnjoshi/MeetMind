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
    public static let requiredModelIDs = ["whisper-large", "diarization", "qwen-1.7b"]
    public init() {}

    public func removeCheckpoint(meetingID: UUID) throws {
        guard !running else { throw OfflineError.unavailable("Wait for the current analysis to finish or pause it first.") }
        let url = try OfflineModelStore.privateDirectory("MeetingCheckpoints").appendingPathComponent(meetingID.uuidString + ".json")
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
        defer { running = false }
        guard audio.isFileURL else { throw OfflineError.unavailable("Choose a recording saved on this iPhone.") }
        let duration = try await AVURLAsset(url: audio).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600 else {
            throw OfflineError.unavailable("Offline analysis supports recordings up to 60 minutes. Your audio is preserved.")
        }
        let profiles = try requiredProfiles()
        // Verify all dependencies before modifying any saved result.
        var folders: [URL] = []
        for profile in profiles { folders.append(try await OfflineModelStore.shared.verifiedFolder(profile)) }
        let attributes = try FileManager.default.attributesOfItem(atPath: audio.path)
        let signature = "\(audio.lastPathComponent)|\(attributes[.size] ?? 0)|\(attributes[.modificationDate] ?? Date.distantPast)|\(meetingDate.timeIntervalSince1970)|\(timezone)|\(profiles.map(\.revision).joined(separator: ","))|v1"
        let checkpointURL = try OfflineModelStore.privateDirectory("MeetingCheckpoints")
            .appendingPathComponent(meetingID.uuidString + ".json")
        var checkpoint = MeetingAnalysisCheckpoint(sourceSignature: signature, stage: .transcription,
            turns: [], speakers: [], analysis: [], analyzedChunks: 0)
        if let data = try? Data(contentsOf: checkpointURL),
           let saved = try? JSONDecoder().decode(MeetingAnalysisCheckpoint.self, from: data),
           saved.sourceSignature == signature { checkpoint = saved }
        func save() throws {
            try JSONEncoder().encode(checkpoint).write(to: checkpointURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if checkpoint.stage == .transcription {
            try checkConditions()
            await progress(.transcription)
            checkpoint.turns = Self.splitTurns(try await LocalSpeech.transcribe(audio: audio, folder: folders[0]))
            guard !checkpoint.turns.isEmpty else { throw OfflineError.unavailable("No speech was recognized. Your recording is preserved.") }
            checkpoint.stage = .speakers
            try save()
        }
        if checkpoint.stage == .speakers {
            try checkConditions()
            await progress(.speakers)
            checkpoint.speakers = try await LocalSpeech.diarize(audio: audio, folder: folders[1])
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
            let model = try LocalLanguageModel(url: folders[2].appendingPathComponent("model.gguf"))
            for index in checkpoint.analyzedChunks..<chunks.count {
                try checkConditions()
                let result = try model.analyze(turns: chunks[index], meetingDate: meetingDate, timezone: timezone)
                try result.validate(against: chunks[index])
                checkpoint.analysis.append(result)
                checkpoint.analyzedChunks = index + 1
                try save()
            }
            checkpoint.stage = .completed
            try save()
        }
        try Task.checkCancellation()
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
            let text = Array(turn.text)
            if text.count <= 600 {
                if !text.isEmpty { fragments.append(turn) }
                continue
            }
            for offset in stride(from: 0, to: text.count, by: 600) {
                let end = min(offset + 600, text.count)
                fragments.append(AnalysisTurn(id: "\(turn.id).\(offset / 600)",
                    text: String(text[offset..<end]), start: turn.start, end: turn.end, speaker: turn.speaker))
            }
        }
        return fragments
    }

    static func analysisChunks(_ turns: [AnalysisTurn]) -> [[AnalysisTurn]] {
        let fragments = splitTurns(turns)
        var result: [[AnalysisTurn]] = [], chunk: [AnalysisTurn] = []
        var count = 0
        for turn in fragments {
            if count + turn.text.count > 1600 && !chunk.isEmpty {
                result.append(chunk)
                chunk = Array(chunk.suffix(1))
                count = chunk.reduce(0) { $0 + $1.text.count }
            }
            chunk.append(turn)
            count += turn.text.count
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
