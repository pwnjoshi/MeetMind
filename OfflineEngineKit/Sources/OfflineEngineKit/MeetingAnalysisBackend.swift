import Foundation

/// Keeps orchestration testable without downloading models or replacing the
/// actual production inference path with a heuristic fallback.
protocol MeetingAnalysisSession {
    var inputTokenLimit: Int { get }
    func inputTokenCount(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> Int
    func analyze(turns: [AnalysisTurn], meetingDate: Date, timezone: String, question: String?) throws -> LocalAnalysisResult
}

extension LocalLanguageModel: MeetingAnalysisSession {}

protocol MeetingAnalysisBackend: Sendable {
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL
    func transcribe(audio: URL, folder: URL) async throws -> [AnalysisTurn]
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan]
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession
}

struct LocalMeetingAnalysisBackend: MeetingAnalysisBackend {
    func verifiedFolder(_ profile: ModelProfile) async throws -> URL {
        try await OfflineModelStore.shared.verifiedFolder(profile)
    }
    func transcribe(audio: URL, folder: URL) async throws -> [AnalysisTurn] {
        try await LocalSpeech.transcribe(audio: audio, folder: folder)
    }
    func diarize(audio: URL, folder: URL) async throws -> [SpeakerSpan] {
        try await LocalSpeech.diarize(audio: audio, folder: folder)
    }
    func makeSession(folder: URL, configuration: LocalModelConfiguration) throws -> any MeetingAnalysisSession {
        try LocalLanguageModel(url: folder.appendingPathComponent("model.gguf"), configuration: configuration)
    }
}
