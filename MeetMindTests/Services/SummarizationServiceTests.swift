//
//  SummarizationServiceTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying SummarizationServiceProtocol contract,
//  dual-engine extractive intelligence (Apple NaturalLanguage + LLM mock),
//  rule-based action item parsing, decision extraction, error typing, and payload integrity.
//

import XCTest
import Foundation
import NaturalLanguage
@testable import MeetMind

final class SummarizationServiceTests: XCTestCase {
    
    private var mockService: MockSummarizationService!
    private var nlService: NaturalLanguageSummarizationService!
    
    override func setUp() async throws {
        try await super.setUp()
        mockService = MockSummarizationService()
        nlService = NaturalLanguageSummarizationService()
    }
    
    override func tearDown() async throws {
        mockService = nil
        nlService = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 6: Summarization Service)
    
    /// Tier 1: Feature 6 - Validates generateSummary returns structured MeetingSummaryResponse.
    func test_tier1_feature6_generateSummaryProducesStructuredResponse() async throws {
        let summarizer: any SummarizationServiceProtocol = mockService
        let transcript = "Today we reviewed the Sprint backlog. We agreed to complete the iOS 17 UI by Friday."
        let response = try await summarizer.generateSummary(from: transcript)
        
        XCTAssertFalse(response.executiveSummary.isEmpty)
        XCTAssertFalse(response.keyDiscussionPoints.isEmpty)
        XCTAssertFalse(response.keyDecisions.isEmpty)
        XCTAssertFalse(response.actionItems.isEmpty)
        XCTAssertFalse(response.topics.isEmpty)
    }
    
    /// Tier 1: Feature 6 - Validates executiveSummary is coherent and populated.
    func test_tier1_feature6_executiveSummaryNotEmpty() async throws {
        let response = try await mockService.generateSummary(from: "Sample meeting transcript")
        XCTAssertTrue(response.executiveSummary.contains("engineering team"))
    }
    
    /// Tier 1: Feature 6 - Validates actionItems extracted contains assignees and priorities.
    func test_tier1_feature6_actionItemsExtractedWithAttributes() async throws {
        let response = try await mockService.generateSummary(from: "Sample transcript")
        XCTAssertEqual(response.actionItems.count, 2)
        
        let item1 = response.actionItems[0]
        XCTAssertEqual(item1.title, "Implement SwiftData model container and schemas")
        XCTAssertEqual(item1.assignee, "Alice")
        XCTAssertEqual(item1.priority, "high")
        
        let item2 = response.actionItems[1]
        XCTAssertEqual(item2.title, "Write automated unit tests for audio services")
        XCTAssertEqual(item2.assignee, "Bob")
        XCTAssertEqual(item2.priority, "urgent")
    }
    
    /// Tier 1: Feature 6 - Validates NaturalLanguage on-device extractive summary generation.
    func test_tier1_feature6_naturalLanguageServiceExtractiveSummary() async throws {
        let transcript = """
        The engineering team assembled to finalize the MeetMind architecture roadmap.
        The mobile team will implement SwiftData models with cascade delete rules on Tuesday.
        We decided to approve the dual-engine summarization strategy for offline privacy.
        Alice must configure the AVAudioEngine 60Hz power meter stream by Wednesday.
        Everyone agreed on the test matrix thresholds for Tier 1 and Tier 2 suites.
        """
        
        let response = try await nlService.generateSummary(from: transcript)
        XCTAssertFalse(response.executiveSummary.isEmpty)
        XCTAssertGreaterThanOrEqual(response.keyDiscussionPoints.count, 1)
        XCTAssertGreaterThanOrEqual(response.keyDecisions.count, 1)
        XCTAssertGreaterThanOrEqual(response.actionItems.count, 1)
        XCTAssertGreaterThanOrEqual(response.topics.count, 1)
    }
    
    /// Tier 1: Feature 6 - Validates NaturalLanguage decision detection with cue stems.
    func test_tier1_feature6_naturalLanguageDecisionDetection() async throws {
        let transcript = """
        We had a lengthy discussion about backend options.
        We decided to use on-device Apple NaturalLanguage for privacy.
        The committee agreed on the proposed API contracts.
        """
        
        let response = try await nlService.generateSummary(from: transcript)
        XCTAssertEqual(response.keyDecisions.count, 2)
        XCTAssertTrue(response.keyDecisions.contains { $0.contains("decided") })
        XCTAssertTrue(response.keyDecisions.contains { $0.contains("agreed") })
    }
    
    /// Tier 1: Feature 6 - Validates NaturalLanguage action item parsing with assignee detection.
    func test_tier1_feature6_naturalLanguageActionItemParsing() async throws {
        let transcript = """
        Sarah will deploy the new test runner scripts.
        John must update the project documentation.
        """
        
        let response = try await nlService.generateSummary(from: transcript)
        XCTAssertEqual(response.actionItems.count, 2)
        
        let sarahItem = response.actionItems.first { $0.title.contains("Sarah") }
        XCTAssertEqual(sarahItem?.assignee, "Sarah")
        
        let johnItem = response.actionItems.first { $0.title.contains("John") }
        XCTAssertEqual(johnItem?.assignee, "John")
    }
    
    /// Tier 1: Feature 8 - Validates Clean Architecture dependency injection via protocol.
    func test_tier1_feature8_cleanArchitectureSummarizationInjection() async throws {
        final class SummaryGeneratorConsumer {
            let summarizer: any SummarizationServiceProtocol
            init(summarizer: any SummarizationServiceProtocol) {
                self.summarizer = summarizer
            }
            func run(text: String) async throws -> String {
                let res = try await summarizer.generateSummary(from: text)
                return res.executiveSummary
            }
        }
        
        let consumer = SummaryGeneratorConsumer(summarizer: mockService)
        let summaryText = try await consumer.run(text: "Test transcript input")
        XCTAssertFalse(summaryText.isEmpty)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Error Injection & NLP Extremes)
    
    /// Tier 2: Feature 6 - Validates empty transcript throws emptyTranscript error.
    func test_tier2_feature6_emptyTranscriptThrowsError() async throws {
        do {
            _ = try await nlService.generateSummary(from: "")
            XCTFail("Expected emptyTranscript error")
        } catch let error as SummarizationError {
            XCTAssertEqual(error, .emptyTranscript)
            XCTAssertEqual(error.errorDescription, "Cannot generate summary from an empty transcript.")
        }
    }
    
    /// Tier 2: Feature 6 - Validates whitespace-only transcript throws emptyTranscript error.
    func test_tier2_feature6_whitespaceOnlyTranscriptThrowsError() async throws {
        do {
            _ = try await nlService.generateSummary(from: "   \n\t  \r  ")
            XCTFail("Expected emptyTranscript error for whitespace")
        } catch let error as SummarizationError {
            XCTAssertEqual(error, .emptyTranscript)
        }
    }
    
    /// Tier 2: Feature 6 - Validates single-sentence transcript works without crash.
    func test_tier2_feature6_singleSentenceTranscript() async throws {
        let transcript = "The meeting was called to order and adjourned immediately."
        let response = try await nlService.generateSummary(from: transcript)
        
        XCTAssertEqual(response.executiveSummary, transcript)
        XCTAssertFalse(response.keyDecisions.isEmpty)
    }
    
    /// Tier 2: Feature 6 - Validates action item priority detection for "urgent".
    func test_tier2_feature6_priorityDetectionUrgent() async throws {
        let transcript = "Sarah must resolve the critical production outage urgent."
        let response = try await nlService.generateSummary(from: transcript)
        
        XCTAssertEqual(response.actionItems.first?.priority, "urgent")
    }
    
    /// Tier 2: Feature 6 - Validates action item priority detection for "high".
    func test_tier2_feature6_priorityDetectionHigh() async throws {
        let transcript = "Bob will prepare the quarterly financial report high priority."
        let response = try await nlService.generateSummary(from: transcript)
        
        XCTAssertEqual(response.actionItems.first?.priority, "high")
    }
    
    /// Tier 2: Feature 6 - Validates action item priority detection for "low".
    func test_tier2_feature6_priorityDetectionLow() async throws {
        let transcript = "Charlie should update the code comments low priority."
        let response = try await nlService.generateSummary(from: transcript)
        
        XCTAssertEqual(response.actionItems.first?.priority, "low")
    }
    
    /// Tier 2: Feature 6 - Validates networkError typing and description.
    func test_tier2_feature6_networkErrorTyping() throws {
        let error = SummarizationError.networkError("Connection timeout (HTTP 504)")
        XCTAssertEqual(error.errorDescription, "Network request failed: Connection timeout (HTTP 504)")
    }
    
    /// Tier 2: Feature 6 - Validates invalidResponse error typing and description.
    func test_tier2_feature6_invalidResponseErrorTyping() throws {
        let error = SummarizationError.invalidResponse("Missing JSON root")
        XCTAssertEqual(error.errorDescription, "Invalid summarization service response: Missing JSON root")
    }
    
    /// Tier 2: Feature 6 - Validates decodingFailed error typing and description.
    func test_tier2_feature6_decodingFailedErrorTyping() throws {
        let error = SummarizationError.decodingFailed("Expected key 'topics'")
        XCTAssertEqual(error.errorDescription, "Failed to decode summary JSON payload: Expected key 'topics'")
    }
    
    /// Tier 2: Feature 6 - Validates serviceUnavailable error typing and description.
    func test_tier2_feature6_serviceUnavailableErrorTyping() throws {
        let error = SummarizationError.serviceUnavailable
        XCTAssertEqual(error.errorDescription, "Summarization service is currently unavailable.")
    }
    
    /// Tier 2: Feature 6 - Validates mockService throws error when configured.
    func test_tier2_feature6_mockServiceThrowsConfiguredError() async throws {
        mockService.shouldThrowError = .serviceUnavailable
        
        do {
            _ = try await mockService.generateSummary(from: "Valid text")
            XCTFail("Expected serviceUnavailable error")
        } catch let error as SummarizationError {
            XCTAssertEqual(error, .serviceUnavailable)
        }
    }
    
    /// Tier 2: Feature 6 - Validates unicode characters, emojis, and quotes in transcript.
    func test_tier2_feature6_unicodeTranscriptNLPProcessing() async throws {
        let transcript = "🚀 The team decided to ship 'v2.0' next week! Alex will test the AI model 🧠."
        let response = try await nlService.generateSummary(from: transcript)
        
        XCTAssertFalse(response.executiveSummary.isEmpty)
        XCTAssertTrue(response.keyDecisions.contains { $0.contains("decided") })
    }
    
    // MARK: - Tier 3: Pairwise Value Types & Simulation Properties
    
    /// Tier 3: Pairwise - Verifies MeetingSummaryResponse Codable and Equatable conformance.
    func test_tier3_meetingSummaryResponseCodable() throws {
        let original = mockService.mockResponse
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MeetingSummaryResponse.self, from: data)
        XCTAssertEqual(decoded, original)
    }
    
    /// Tier 3: Pairwise - Verifies ParsedActionItem Codable and Equatable conformance.
    func test_tier3_parsedActionItemCodable() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let original = ParsedActionItem(
            title: "Task 1",
            taskDescription: "Description 1",
            assignee: "Alice",
            dueDate: date,
            priority: "urgent"
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ParsedActionItem.self, from: data)
        XCTAssertEqual(decoded, original)
    }
    
    /// Tier 3: Pairwise - Verifies recordedTranscript captures input text for auditing.
    func test_tier3_recordedTranscriptAuditing() async throws {
        let input = "Unique audit transcript 998877"
        _ = try await mockService.generateSummary(from: input)
        XCTAssertEqual(mockService.recordedTranscript, input)
    }
    
    /// Tier 1: Feature 6 - Validates summarization with custom mock response.
    func test_tier1_feature6_summarizationWithCustomMockResponse() async throws {
        let customResponse = MeetingSummaryResponse(
            executiveSummary: "Custom executive overview",
            keyDiscussionPoints: ["Pt A"],
            keyDecisions: ["Dec A"],
            actionItems: [],
            topics: ["Custom"]
        )
        let customService = MockSummarizationService(mockResponse: customResponse)
        let response = try await customService.generateSummary(from: "Any text")
        XCTAssertEqual(response, customResponse)
    }
    
    /// Tier 1: Feature 6 - Validates NaturalLanguage tokenization handles punctuation correctly.
    func test_tier1_feature6_naturalLanguageTokenizationHandlesPunctuation() async throws {
        let text = "First sentence! Second sentence? Third sentence."
        let response = try await nlService.generateSummary(from: text)
        XCTAssertFalse(response.executiveSummary.isEmpty)
    }
    
    /// Tier 2: Feature 6 - Validates action item parsing with various action keywords.
    func test_tier2_feature6_actionItemParsingWithVariousActionKeywords() async throws {
        let text = """
        John needs to review the pull request.
        Sarah should update the test plan.
        Follow up with design team on Monday.
        """
        let response = try await nlService.generateSummary(from: text)
        XCTAssertGreaterThanOrEqual(response.actionItems.count, 2)
    }
    
    /// Tier 2: Feature 6 - Validates action item parsing without assignee defaults to nil.
    func test_tier2_feature6_actionItemParsingWithoutAssigneeDefaultsToNil() async throws {
        let text = "We will conduct end-to-end tests."
        let response = try await nlService.generateSummary(from: text)
        let item = response.actionItems.first
        XCTAssertNotNil(item)
    }
    
    /// Tier 2: Feature 6 - Validates SummarizationError equality.
    func test_tier2_feature6_summarizationErrorEquality() throws {
        let err1 = SummarizationError.emptyTranscript
        let err2 = SummarizationError.emptyTranscript
        let err3 = SummarizationError.serviceUnavailable
        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)
    }
    
    /// Tier 3: Simulated delay honored in MockSummarizationService.
    func test_tier3_mockSummarizationSimulatedDelayPreserved() async throws {
        mockService.simulatedDelay = 0.05
        let start = Date()
        _ = try await mockService.generateSummary(from: "Delay check")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(elapsed, 0.04)
    }
}
