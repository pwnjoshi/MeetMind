import Foundation

/// Parsed action item extracted from meeting transcription
public struct ParsedActionItem: Codable, Sendable, Equatable {
    public let title: String
    public let taskDescription: String
    public let assignee: String?
    public let dueDate: Date?
    public let priority: String
    
    public init(
        title: String,
        taskDescription: String = "",
        assignee: String? = nil,
        dueDate: Date? = nil,
        priority: String = "medium"
    ) {
        self.title = title
        self.taskDescription = taskDescription
        self.assignee = assignee
        self.dueDate = dueDate
        self.priority = priority
    }
}

/// Structured summary payload produced by summarization services
public struct MeetingSummaryResponse: Codable, Sendable, Equatable {
    public let executiveSummary: String
    public let keyDiscussionPoints: [String]
    public let keyDecisions: [String]
    public let actionItems: [ParsedActionItem]
    public let topics: [String]
    
    public init(
        executiveSummary: String,
        keyDiscussionPoints: [String] = [],
        keyDecisions: [String] = [],
        actionItems: [ParsedActionItem] = [],
        topics: [String] = []
    ) {
        self.executiveSummary = executiveSummary
        self.keyDiscussionPoints = keyDiscussionPoints
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.topics = topics
    }
}

/// Errors thrown by the summarization service
public enum SummarizationError: LocalizedError, Sendable, Equatable {
    case emptyTranscript
    case networkError(String)
    case invalidResponse(String)
    case decodingFailed(String)
    case serviceUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Cannot generate summary from an empty transcript."
        case .networkError(let reason):
            return "Network request failed: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid summarization service response: \(reason)"
        case .decodingFailed(let reason):
            return "Failed to decode summary JSON payload: \(reason)"
        case .serviceUnavailable:
            return "Summarization service is currently unavailable."
        }
    }
}

/// Protocol defining the summarization service contract
public protocol SummarizationServiceProtocol: AnyObject, Sendable {
    /// Generates executive summary, key points, decisions, and action items from transcript
    func generateSummary(from transcriptText: String) async throws -> MeetingSummaryResponse
}
