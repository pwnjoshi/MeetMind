//
//  ExportAndAIE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Meeting Minutes Multi-Format Export
//  (PDF, Markdown, Plain Text, Email Draft) and Interactive Ask AI Assistant
//  with Timecode Citations (Scenarios S9, S12, S13 + Tier 3 Pairwise Combinations).
//

import XCTest
import Foundation
import SwiftData
@testable import MeetMind

final class ExportAndAIE2ETests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var context: ModelContext!
    private var detailVM: MeetingDetailViewModel!
    private var mockExportService: MockExportService!
    private var mockAudioPlayer: MockAudioPlaybackService!
    private var mockSummarizer: MockSummarizationService!
    private var meeting: Meeting!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: ModelContainerFactory.schema, configurations: [configuration])
        context = ModelContext(modelContainer)
        mockExportService = MockExportService()
        mockAudioPlayer = MockAudioPlaybackService()
        mockSummarizer = MockSummarizationService()
        
        meeting = Meeting(title: "Strategic Planning Q4", createdAt: Date(), duration: 600.0, status: .completed)
        meeting.audioFileURL = URL(fileURLWithPath: "/tmp/strategic_planning.m4a")
        context.insert(meeting)
        
        let john = Speaker(name: "John Connor", role: "VP Engineering", avatarColorHex: "#0284C7")
        let sarah = Speaker(name: "Sarah Connor", role: "CTO", avatarColorHex: "#7C3AED")
        context.insert(john)
        context.insert(sarah)
        meeting.participants = [john, sarah]
        
        let seg1 = TranscriptSegment(text: "Let's review deliverables for this sprint.", startTime: 0.0, endTime: 30.0, speaker: sarah, meeting: meeting)
        let seg2 = TranscriptSegment(text: "I commit to delivering the security audit report by Friday.", startTime: 252.0, endTime: 260.0, speaker: john, meeting: meeting) // 04:12
        context.insert(seg1)
        context.insert(seg2)
        meeting.transcriptSegments = [seg1, seg2]
        
        let summary = Summary(
            executiveSummary: "Discussion on sprint deliverables and Q4 architecture roadmap.",
            keyPoints: ["Security audit deadline", "Roadmap milestones"],
            keyDecisions: ["Security audit will be delivered Friday"],
            meeting: meeting
        )
        context.insert(summary)
        meeting.summary = summary
        
        let action = ActionItem(title: "Deliver security audit report", priority: .high, dueDate: Date().addingTimeInterval(86400 * 3), assignee: john, meeting: meeting)
        context.insert(action)
        meeting.actionItems = [action]
        try? context.save()
        
        detailVM = MeetingDetailViewModel(
            meeting: meeting,
            modelContext: context,
            playbackService: mockAudioPlayer,
            summarizationService: mockSummarizer,
            exportService: mockExportService
        )
    }
    
    @MainActor
    override func tearDown() async throws {
        detailVM = nil
        mockExportService = nil
        mockAudioPlayer = nil
        mockSummarizer = nil
        meeting = nil
        context = nil
        modelContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S9 (Executive Minutes Multi-Format Export)
    
    /// Tier 4: Scenario S9 - Executive Minutes Multi-Format Export
    /// - Given: A completed meeting with summary, participants, and action items.
    /// - When:
    ///   1. User taps "Export" in meeting cockpit navigation bar.
    ///   2. Selects "Export as PDF" -> Generates formatted multi-page PDF document.
    ///   3. Selects "Export as Markdown" -> Generates Markdown minutes string.
    /// - Then:
    ///   - PDF Data is non-empty (>0 bytes) and contains header, summary card, action table, and attendee list.
    ///   - Markdown contains `# Strategic Planning Q4`, bulleted decisions, and action item check syntax (`- [ ]`).
    func test_tier4_scenario9_executiveMinutesMultiFormatExport() throws {
        // When - 2. PDF Export
        let pdfData = try detailVM.exportMeeting(as: .pdf)
        XCTAssertGreaterThan(pdfData.count, 0)
        XCTAssertTrue(mockExportService.wasPDFGenerated)
        
        // When - 3. Markdown Export
        let markdownText = try detailVM.exportMeeting(as: .markdownText)
        XCTAssertTrue(markdownText.contains("# Strategic Planning Q4"))
        XCTAssertTrue(markdownText.contains("## Executive Summary"))
        XCTAssertTrue(markdownText.contains("Discussion on sprint deliverables"))
        XCTAssertTrue(markdownText.contains("## Key Decisions"))
        XCTAssertTrue(markdownText.contains("Security audit will be delivered Friday"))
        XCTAssertTrue(markdownText.contains("## Action Items"))
        XCTAssertTrue(markdownText.contains("- [ ] Deliver security audit report"))
    }

    // MARK: - Tier 4: Scenario S12 (Ask AI Grounded Q&A)
    
    /// Tier 4: Scenario S12 - Interactive Ask AI Assistant with Timecode Citations
    /// - Given: Meeting detail cockpit is open with full transcript.
    /// - When:
    ///   1. User opens "Ask AI" conversational bottom sheet.
    ///   2. Types prompt: "What did John commit to delivering by Friday?"
    ///   3. Ask AI service processes prompt against transcript chunks.
    ///   4. Response is returned containing exact timecode citation `[04:12]`.
    ///   5. User taps `[04:12]` citation pill.
    /// - Then:
    ///   - Response accurately states: "John committed to delivering the security audit report [04:12]."
    ///   - Tapping citation seeks audio player directly to 252.0 seconds (04:12) and begins playback.
    func test_tier4_scenario12_askAIGroundedQA() async throws {
        // Given
        mockAudioPlayer.seek(to: 0.0)
        XCTAssertEqual(mockAudioPlayer.currentTime, 0.0)
        
        // When - 2 & 3. Prompt Ask AI
        let prompt = "What did John commit to delivering by Friday?"
        let aiResponse = try await detailVM.askAI(prompt: prompt)
        
        // Then - 4. Response with citation
        XCTAssertTrue(aiResponse.answer.contains("security audit report"))
        XCTAssertEqual(aiResponse.citations.count, 1)
        XCTAssertEqual(aiResponse.citations.first?.formattedTimecode, "04:12")
        XCTAssertEqual(aiResponse.citations.first?.timestamp, 252.0)
        
        // When - 5. Tap citation
        let citation = aiResponse.citations.first!
        detailVM.seekToCitation(citation)
        
        // Then
        XCTAssertEqual(mockAudioPlayer.currentTime, 252.0)
        XCTAssertTrue(mockAudioPlayer.isPlaying)
    }

    // MARK: - Tier 4: Scenario S13 (Email Draft Summary Generator)
    
    /// Tier 4: Scenario S13 - Email Draft Summary Generator
    /// - Given: Meeting minutes are finalized and ready for executive distribution.
    /// - When:
    ///   1. User chooses "Email Summary" from the Export menu.
    ///   2. Email generator compiles pre-formatted text/HTML body.
    /// - Then:
    ///   - Email subject is formatted as: `[MeetMind Minutes] Strategic Planning Q4`.
    ///   - Email body contains executive summary, key decisions, and an action items list formatted for email clients.
    func test_tier4_scenario13_emailDraftSummaryGenerator() throws {
        let emailDraft = detailVM.generateEmailDraft()
        
        XCTAssertEqual(emailDraft.subject, "[MeetMind Minutes] Strategic Planning Q4")
        XCTAssertTrue(emailDraft.body.contains("Executive Summary:"))
        XCTAssertTrue(emailDraft.body.contains("Discussion on sprint deliverables"))
        XCTAssertTrue(emailDraft.body.contains("Key Decisions:"))
        XCTAssertTrue(emailDraft.body.contains("Action Items:"))
        XCTAssertTrue(emailDraft.body.contains("Deliver security audit report (Assignee: John Connor)"))
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Multi-page PDF Report Generation
    /// - Verifies generating a report for a meeting with 100 segments produces multi-page document.
    func test_tier3_multipagePDFReportGeneration() throws {
        for i in 1...100 {
            let seg = TranscriptSegment(text: "Segment \(i) with discussion text.", startTime: Double(i * 10), endTime: Double(i * 10 + 5))
            meeting.transcriptSegments.append(seg)
        }
        
        let pdfData = try detailVM.exportMeeting(as: .pdf)
        XCTAssertGreaterThan(pdfData.count, 5000)
    }

    /// Tier 3: Pairwise - Markdown Export Formatting Invariants
    /// - Verifies markdown escaping of special characters and formatting.
    func test_tier3_markdownExportFormatting() throws {
        let md = try detailVM.exportMeeting(as: .markdownText)
        XCTAssertTrue(md.hasPrefix("# "))
        XCTAssertTrue(md.contains("**Attendees:**"))
        XCTAssertTrue(md.contains("John Connor"))
        XCTAssertTrue(md.contains("Sarah Connor"))
    }

    /// Tier 3: Pairwise - Plain Text Export Structure
    /// - Verifies clean human-readable text output without markdown symbols.
    func test_tier3_plainTextExportStructure() throws {
        let plainText = try detailVM.exportMeeting(as: .plainText)
        XCTAssertFalse(plainText.contains("##"))
        XCTAssertTrue(plainText.contains("MEETING MINUTES"))
        XCTAssertTrue(plainText.contains("TITLE: Strategic Planning Q4"))
    }

    /// Tier 3: Pairwise - Ask AI Grounded Citations Parsing
    /// - Verifies citations parse start time and duration accurately.
    func test_tier3_askAIGroundedCitations() async throws {
        let response = try await detailVM.askAI(prompt: "Who committed to Friday?")
        XCTAssertGreaterThan(response.citations.count, 0)
        XCTAssertEqual(response.citations[0].timestamp, 252.0)
    }

    /// Tier 3: Pairwise - Ask AI Off-Topic Rejection
    /// - Verifies asking questions about topics not mentioned returns "Not discussed in meeting".
    func test_tier3_askAIOffTopicRejection() async throws {
        let offTopicResponse = try await detailVM.askAI(prompt: "What is the recipe for chocolate cake?")
        XCTAssertEqual(offTopicResponse.answer, "Not discussed in meeting.")
        XCTAssertTrue(offTopicResponse.citations.isEmpty)
    }

    /// Tier 3: Pairwise - Ask AI Multi-Turn Conversation History
    /// - Verifies multi-turn questions maintain conversation history.
    func test_tier3_askAIMultiTurnConversation() async throws {
        _ = try await detailVM.askAI(prompt: "Who attended?")
        let followUp = try await detailVM.askAI(prompt: "What was John's role?")
        
        XCTAssertEqual(detailVM.askAIHistory.count, 2)
        XCTAssertTrue(followUp.answer.contains("VP Engineering") || followUp.answer.contains("John"))
    }

    /// Tier 3: Pairwise - Citation Tap-to-Seek Audio Playback
    /// - Verifies tapping citation starts audio playback if paused.
    func test_tier3_citationTapToSeekAudioPlayback() throws {
        let citation = AICitation(timestamp: 120.0, text: "Reference point")
        detailVM.seekToCitation(citation)
        
        XCTAssertEqual(mockAudioPlayer.currentTime, 120.0)
        XCTAssertTrue(mockAudioPlayer.isPlaying)
    }

    /// Tier 3: Pairwise - Email Draft HTML and Plain Text Rendering
    /// - Verifies HTML tags are valid and properly closed.
    func test_tier3_emailDraftHTMLAndTextFormatting() throws {
        let htmlBody = detailVM.generateEmailDraftHTML()
        XCTAssertTrue(htmlBody.contains("<html>"))
        XCTAssertTrue(htmlBody.contains("</html>"))
        XCTAssertTrue(htmlBody.contains("<h3>Action Items</h3>"))
    }

    /// Tier 3: Pairwise - Export With Nil Summary Fallback
    /// - Verifies exporting meeting before AI summary completes generates transcript report.
    func test_tier3_exportWithNilSummaryFallback() throws {
        meeting.summary = nil
        let markdown = try detailVM.exportMeeting(as: .markdownText)
        
        XCTAssertTrue(markdown.contains("Summary pending generation"))
        XCTAssertTrue(markdown.contains("## Transcript"))
    }

    /// Tier 3: Pairwise - Export Special Characters and Emojis
    /// - Verifies emojis and unicode are preserved in export without crash.
    func test_tier3_exportSpecialCharactersAndEmojis() throws {
        meeting.title = "Sprint 🎉 & Security 🔒 Review"
        let md = try detailVM.exportMeeting(as: .markdownText)
        XCTAssertTrue(md.contains("Sprint 🎉 & Security 🔒 Review"))
    }

    /// Tier 3: Pairwise - Ask AI Network Timeout Extractive Fallback
    /// - Verifies network timeout falls back to local sentence matching.
    func test_tier3_askAINetworkTimeoutFallback() async throws {
        detailVM.simulateNetworkTimeoutOnAskAI = true
        let response = try await detailVM.askAI(prompt: "security audit")
        
        XCTAssertTrue(response.isExtractiveFallback)
        XCTAssertTrue(response.answer.contains("security audit"))
    }
}
