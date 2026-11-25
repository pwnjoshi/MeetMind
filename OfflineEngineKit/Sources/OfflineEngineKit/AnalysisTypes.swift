import Foundation

public enum OfflineAnalysisContract {
    public static let promptVersion = "meeting-analysis-v12"
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
    /// Undecided, hypothetical or still-open items. The model grammar emits only
    /// three arrays; the reducer derives this list. Absent in checkpoints saved
    /// by older versions, which decode with an empty list.
    public let openIssues: [SupportedPoint]

    public init(discussion: [SupportedPoint], decisions: [SupportedPoint], tasks: [SuggestedTask],
                openIssues: [SupportedPoint] = []) {
        self.discussion = discussion
        self.decisions = decisions
        self.tasks = tasks
        self.openIssues = openIssues
    }

    private enum CodingKeys: String, CodingKey { case discussion, decisions, tasks, openIssues }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discussion = try container.decode([SupportedPoint].self, forKey: .discussion)
        decisions = try container.decode([SupportedPoint].self, forKey: .decisions)
        tasks = try container.decode([SuggestedTask].self, forKey: .tasks)
        openIssues = try container.decodeIfPresent([SupportedPoint].self, forKey: .openIssues) ?? []
    }

    /// Keeps only items whose every quote is an exact substring of its cited
    /// turn, and tasks with a valid title, category and priority. A small local
    /// model sometimes copies a prompt example or garbles one quote; dropping
    /// that item is safer than discarding the whole meeting, and never invents.
    public func sanitized(against turns: [AnalysisTurn]) -> LocalAnalysisResult {
        let sources = Dictionary(turns.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        let categories = Set(["Follow-up", "Research", "Create/Update", "Review/Approve", "Coordination", "Other"])
        let priorities = Set(["low", "medium", "high", "urgent"])
        func grounded(_ evidence: [SourceEvidence]) -> Bool {
            !evidence.isEmpty && evidence.allSatisfy { item in
                !item.quote.isEmpty && (sources[item.turnID]?.contains(item.quote) == true)
            }
        }
        let spoken = turns.map(\.text).joined(separator: " ")
        func keep(_ point: SupportedPoint) -> Bool {
            !point.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && grounded(point.evidence)
                && !Self.copiesPromptExample(point.text, spoken: spoken)
        }
        let validTasks = tasks.filter { task in
            let titled = !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let priorityOK = task.priority.map { priorities.contains($0) } ?? true
            let copied = [task.title, task.owner ?? "", task.deadlineText ?? ""]
                .contains { Self.copiesPromptExample($0, spoken: spoken) }
            return titled && categories.contains(task.category) && priorityOK && grounded(task.evidence) && !copied
        }
        return LocalAnalysisResult(discussion: discussion.filter(keep), decisions: decisions.filter(keep),
                                   tasks: validTasks, openIssues: openIssues.filter(keep))
    }

    /// Text a small model copied from the prompt's examples instead of the meeting:
    /// a bracketed placeholder such as "[Name]", or the example decision from earlier
    /// prompt versions ("Pune vendor") when nobody in this transcript mentions Pune.
    static func copiesPromptExample(_ text: String, spoken: String) -> Bool {
        if text.contains("[") || text.contains("]") { return true }
        let lower = text.lowercased()
        if lower.contains("pune vendor") || lower.contains("pune venue") {
            let source = spoken.lowercased()
            return !(source.contains("pune") || source.contains("\u{092A}\u{0941}\u{0923}\u{0947}")
                || source.contains("\u{092A}\u{0941}\u{0928}\u{0947}") || source.contains("\u{092A}\u{0942}\u{0928}\u{093E}"))
        }
        return false
    }

    public func validate(against turns: [AnalysisTurn]) throws {
        guard Set(turns.map(\.id)).count == turns.count else {
            throw OfflineError.unavailable("Transcript turn IDs must be unique.")
        }
        let sources = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0.text) })
        let categories = Set(["Follow-up", "Research", "Create/Update", "Review/Approve", "Coordination", "Other"])
        let priorities = Set(["low", "medium", "high", "urgent"])
        guard (discussion + decisions + openIssues).allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw OfflineError.unavailable("Analysis returned an empty supported point. Review the transcript and retry.")
        }
        for task in tasks {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  categories.contains(task.category), task.priority == nil || priorities.contains(task.priority!) else {
                throw OfflineError.unavailable("Analysis returned an invalid task. No results were saved to your meetings.")
            }
        }
        for evidence in discussion.map(\.evidence) + decisions.map(\.evidence) + openIssues.map(\.evidence) + tasks.map(\.evidence) {
            guard !evidence.isEmpty, evidence.allSatisfy({ !$0.quote.isEmpty && (sources[$0.turnID]?.contains($0.quote) == true) }) else {
                throw OfflineError.unavailable("Analysis returned missing or invalid source evidence. Review the transcript and retry.")
            }
        }
    }
}

/// Content-free durations for one analysis run, logged so slow stages can be found
/// on a device without exposing meeting text.
public struct AnalysisStageTimings: Sendable, Equatable {
    public var transcriptionMs = 0
    public var speakersMs = 0
    /// Language model loads, including reloads when the app changes foreground state.
    public var modelLoadMs = 0
    public var modelLoads = 0
    /// Whole minutes stage, including model loads and every chunk.
    public var minutesMs = 0
    /// Per-chunk model time for chunks not reused from recording-time pre-analysis.
    public var chunkMs: [Int] = []
    /// Chunks the language model ran on the CPU because the app was in the background.
    public var cpuChunks = 0
    /// Chunks redone on the CPU after the move to the background interrupted them.
    public var backgroundRetries = 0

    public init() {}

    public var logDescription: String {
        let average = chunkMs.isEmpty ? 0 : chunkMs.reduce(0, +) / chunkMs.count
        return "transcribe_ms=\(transcriptionMs) speakers_ms=\(speakersMs) minutes_ms=\(minutesMs) "
            + "model_load_ms=\(modelLoadMs) model_loads=\(modelLoads) chunks=\(chunkMs.count) "
            + "chunk_avg_ms=\(average) chunk_max_ms=\(chunkMs.max() ?? 0) cpu_chunks=\(cpuChunks) "
            + "background_retries=\(backgroundRetries)"
    }
}
