import Foundation

public final class MockSummarizationService: SummarizationServiceProtocol, @unchecked Sendable {
    public var mockResponse: MeetingSummaryResponse
    public var shouldThrowError: SummarizationError? = nil
    public var recordedTranscript: String? = nil
    public var simulatedDelay: TimeInterval = 0.05
    
    public init(mockResponse: MeetingSummaryResponse? = nil) {
        self.mockResponse = mockResponse ?? MeetingSummaryResponse(
            executiveSummary: "The engineering team reviewed the sprint deliverables and aligned on the iOS 17 architecture milestones.",
            keyDiscussionPoints: [
                "Reviewed SwiftData schema and cascade deletion rules.",
                "Discussed audio recording pipeline with 60Hz power metering.",
                "Agreed on offline speech transcription fallback."
            ],
            keyDecisions: [
                "Approved use of Apple NaturalLanguage framework for offline on-device extraction.",
                "Decided to mandate Sendable value objects across all service protocol boundaries."
            ],
            actionItems: [
                ParsedActionItem(
                    title: "Implement SwiftData model container and schemas",
                    taskDescription: "Create Meeting, TranscriptSegment, Speaker, Summary, ActionItem entities.",
                    assignee: "Alice",
                    dueDate: Date().addingTimeInterval(86400 * 3),
                    priority: "high"
                ),
                ParsedActionItem(
                    title: "Write automated unit tests for audio services",
                    taskDescription: "Cover recording, playback, and scrubbing test cases.",
                    assignee: "Bob",
                    dueDate: Date().addingTimeInterval(86400 * 2),
                    priority: "urgent"
                )
            ],
            topics: ["Architecture", "SwiftData", "Audio", "Testing"]
        )
    }
    
    public func generateSummary(from transcriptText: String) async throws -> MeetingSummaryResponse {
        recordedTranscript = transcriptText
        if let error = shouldThrowError {
            throw error
        }
        if simulatedDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }
        return mockResponse
    }
}
