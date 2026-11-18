import Foundation

public enum OfflineAnalysisContract {
    public static let promptVersion = "meeting-analysis-v2"
}

public struct AnalysisTurn: Codable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let start: Double
    public let end: Double
    public let speaker: String?
    public init(id: String, text: String, start: Double, end: Double, speaker: String?) {
        self.id = id; self.text = text; self.start = start; self.end = end; self.speaker = speaker
    }
}

public struct SourceEvidence: Codable, Sendable {
    public let turnID: String
    public let quote: String
    public init(turnID: String, quote: String) { self.turnID = turnID; self.quote = quote }
}

public struct SuggestedTask: Codable, Sendable {
    public let title: String
    public let category: String
    public let owner: String?
    public let deadlineText: String?
    public let priority: String?
    public let evidence: [SourceEvidence]
}

public struct SupportedPoint: Codable, Sendable {
    public let text: String
    public let evidence: [SourceEvidence]
    public init(text: String, evidence: [SourceEvidence]) { self.text = text; self.evidence = evidence }
}

public struct LocalAnalysisResult: Codable, Sendable {
    public let discussion: [SupportedPoint]
    public let decisions: [SupportedPoint]
    public let tasks: [SuggestedTask]

    public func validate(against turns: [AnalysisTurn]) throws {
        guard Set(turns.map(\.id)).count == turns.count else {
            throw OfflineError.unavailable("Transcript turn IDs must be unique.")
        }
        let sources = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0.text) })
        let categories = Set(["Follow-up", "Research", "Create/Update", "Review/Approve", "Coordination", "Other"])
        let priorities = Set(["low", "medium", "high", "urgent"])
        guard (discussion + decisions).allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw OfflineError.unavailable("Analysis returned an empty supported point. Review the transcript and retry.")
        }
        for task in tasks {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  categories.contains(task.category), task.priority == nil || priorities.contains(task.priority!) else {
                throw OfflineError.unavailable("Analysis returned an invalid task. No results were saved to your meetings.")
            }
        }
        for evidence in discussion.map(\.evidence) + decisions.map(\.evidence) + tasks.map(\.evidence) {
            guard !evidence.isEmpty, evidence.allSatisfy({ !$0.quote.isEmpty && (sources[$0.turnID]?.contains($0.quote) == true) }) else {
                throw OfflineError.unavailable("Analysis returned missing or invalid source evidence. Review the transcript and retry.")
            }
        }
    }
}
