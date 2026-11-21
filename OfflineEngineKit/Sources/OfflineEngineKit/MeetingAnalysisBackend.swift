import Foundation

/// Keeps orchestration testable without downloading models or replacing the
/// actual production inference path with a heuristic fallback.
protocol MeetingAnalysisSession {
    var inputTokenLimit: Int { get }
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult
    /// Participant names and the agenda are untrusted prompt context. Conformers that
    /// ignore them inherit the default, which forwards to the context-free methods.
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?,
                         participants: [String], agenda: String?) throws -> Int
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?,
                 participants: [String], agenda: String?) throws -> LocalAnalysisResult
}

extension MeetingAnalysisSession {
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?,
                         participants: [String], agenda: String?) throws -> Int {
        try inputTokenCount(turns: turns, meetingDate: meetingDate, timezone: timezone, question: question)
    }

    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?,
                 participants: [String], agenda: String?) throws -> LocalAnalysisResult {
        try analyze(turns: turns, meetingDate: meetingDate, timezone: timezone, question: question)
    }
}

extension LocalLanguageModel: MeetingAnalysisSession {}

protocol MeetingAnalysisBackend: Sendable {
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL
    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn]
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan]
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession
    func isInstalled(_ profile: ModelProfile) async -> Bool
}

extension MeetingAnalysisBackend {
    func isInstalled(_ profile: ModelProfile) async -> Bool { true }
}

struct LocalMeetingAnalysisBackend: MeetingAnalysisBackend {
    func isInstalled(_ profile: ModelProfile) async -> Bool {
        await OfflineModelStore.shared.isInstalled(profile)
    }
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL {
        try await OfflineModelStore.shared.verifiedFolder(profile)
    }
    func transcribe(audio: URL, folder: URL, languageCode: String?) async throws -> [AnalysisTurn] {
        try await LocalSpeech.transcribe(audio: audio, folder: folder, languageCode: languageCode)
    }
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] {
        try await LocalSpeech.diarize(audio: audio, folder: folder)
    }
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        try LocalLanguageModel(url: folder.appendingPathComponent("model.gguf"), configuration: configuration)
    }
}
