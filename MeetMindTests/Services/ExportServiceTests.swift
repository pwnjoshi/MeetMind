//
//  ExportServiceTests.swift
//  MeetMindTests
//
//  Comprehensive test suite verifying ExportServiceProtocol contract,
//  multi-format document rendering (PDF header bytes, CommonMark Markdown, Plain Text),
//  boundary handling of empty/sparse meetings, error typing, and Clean Architecture injection.
//

import XCTest
import Foundation
import PDFKit
@testable import MeetMind

@MainActor
final class ExportServiceTests: XCTestCase {
    
    private var mockService: MockExportService!
    private var exportService: ExportService!
    private var sampleMeeting: Meeting!
    
    override func setUp() async throws {
        try await super.setUp()
        mockService = MockExportService()
        exportService = ExportService()
        
        sampleMeeting = Meeting(
            title: "Sprint Review & Release",
            scheduledStartTime: Date(timeIntervalSince1970: 1700000000),
            duration: 1800.0,
            status: .completed
        )
        
        let speaker = Speaker(name: "Alice Johnson", role: "Product Manager")
        sampleMeeting.addParticipant(speaker)
        
        let seg1 = TranscriptSegment(text: "Welcome to the release review.", startTime: 0, endTime: 5, speaker: speaker)
        let seg2 = TranscriptSegment(text: "All features are tested and ready.", startTime: 5, endTime: 12, speaker: speaker)
        sampleMeeting.addTranscriptSegment(seg1)
        sampleMeeting.addTranscriptSegment(seg2)
        
        sampleMeeting.summary = Summary(
            executiveSummary: "Sprint goals achieved with all unit tests passing.",
            keyPoints: ["Model migrations verified", "Audio pipeline hardened"],
            keyDecisions: ["Approved release v1.0.0 for App Store"]
        )
        
        let actionItem = ActionItem(title: "Publish App Store build", isCompleted: true, priority: .urgent, assignee: speaker)
        sampleMeeting.addActionItem(actionItem)
    }
    
    override func tearDown() async throws {
        mockService = nil
        exportService = nil
        sampleMeeting = nil
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Feature Coverage (Feature 7, Feature 53: Export Service Engine)
    
    /// Tier 1: Feature 7 - Validates generatePDFReport returns non-empty Data with %PDF header.
    func test_tier1_feature7_generatePDFReportReturnsData() throws {
        let exporter: any ExportServiceProtocol = mockService
        let data = try exporter.generatePDFReport(for: sampleMeeting)
        
        XCTAssertGreaterThan(data.count, 20)
        let headerString = String(data: data.prefix(5), encoding: .utf8)
        XCTAssertEqual(headerString, "%PDF-")
    }
    
    /// Tier 1: Feature 7 - Validates generateMarkdown contains meeting title and headers.
    func test_tier1_feature7_generateMarkdownContainsTitleAndMetadata() throws {
        let exporter: any ExportServiceProtocol = exportService
        let md = exporter.generateMarkdown(for: sampleMeeting)
        
        XCTAssertTrue(md.contains("# Meeting Minutes: Sprint Review & Release"))
        XCTAssertTrue(md.contains("**Duration**: 30:00"))
        XCTAssertTrue(md.contains("**Status**: Completed"))
    }
    
    /// Tier 1: Feature 7 - Validates generateMarkdown contains attendees section.
    func test_tier1_feature7_generateMarkdownContainsAttendees() throws {
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("## Attendees"))
        XCTAssertTrue(md.contains("- Alice Johnson (Product Manager)"))
    }

    func testReviewedAttendanceAndAgendaAreIncludedInEveryExport() throws {
        let absent = Speaker(name: "Sam Rivera")
        sampleMeeting.addParticipant(absent)
        sampleMeeting.agendaText = "Review the release checklist"
        sampleMeeting.absentParticipantIDs = [absent.id]

        let markdown = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(markdown.contains("## Agenda\n- Review the release checklist"))
        XCTAssertTrue(markdown.contains("## Present\n- Alice Johnson"))
        XCTAssertTrue(markdown.contains("## Absent\n- Sam Rivera"))

        let plainText = exportService.generatePlainText(for: sampleMeeting)
        XCTAssertTrue(plainText.contains("AGENDA:\n• Review the release checklist"))
        XCTAssertTrue(plainText.contains("PRESENT:\n• Alice Johnson"))
        XCTAssertTrue(plainText.contains("ABSENT:\n• Sam Rivera"))

        let data = try exportService.generatePDFReport(for: sampleMeeting)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let pdfText = (pdf.string ?? "").components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertTrue(pdfText.contains("AGENDA Review the release checklist"))
        XCTAssertTrue(pdfText.contains("PRESENT Alice Johnson"))
        XCTAssertTrue(pdfText.contains("ABSENT Sam Rivera"))
    }
    
    /// Tier 1: Feature 7 - Validates generateMarkdown contains executive summary and decisions.
    func test_tier1_feature7_generateMarkdownContainsSummaryAndDecisions() throws {
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("## Executive Summary"))
        XCTAssertTrue(md.contains("Sprint goals achieved with all unit tests passing."))
        XCTAssertTrue(md.contains("## Key Decisions"))
        XCTAssertTrue(md.contains("- Approved release v1.0.0 for App Store"))
    }
    
    /// Tier 1: Feature 7 - Validates generateMarkdown contains action items with checkbox.
    func test_tier1_feature7_generateMarkdownContainsActionItems() throws {
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("## Action Items"))
        XCTAssertTrue(md.contains("- [x] **Publish App Store build**"))
        XCTAssertTrue(md.contains("[Priority: Urgent]"))
    }
    
    /// Tier 1: Feature 7 - Validates generateMarkdown contains diarized transcript timestamps.
    func test_tier1_feature7_generateMarkdownContainsTranscript() throws {
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("## Transcript"))
        XCTAssertTrue(md.contains("**Alice Johnson** [00:00]: Welcome to the release review."))
    }
    
    /// Tier 1: Feature 7 - Validates generatePlainText produces clean ASCII formatted text.
    func test_tier1_feature7_generatePlainTextFormatting() throws {
        let text = exportService.generatePlainText(for: sampleMeeting)
        XCTAssertTrue(text.contains("MEETMIND MINUTES: Sprint Review & Release"))
        XCTAssertTrue(text.contains("ATTENDEES:"))
        XCTAssertTrue(text.contains("EXECUTIVE SUMMARY:"))
        XCTAssertTrue(text.contains("KEY DECISIONS:"))
        XCTAssertTrue(text.contains("ACTION ITEMS:"))
        XCTAssertTrue(text.contains("[X] Publish App Store build"))
    }
    
    /// Tier 1: Feature 8 - Validates Clean Architecture dependency injection via protocol.
    func test_tier1_feature8_cleanArchitectureExportInjection() throws {
        final class MeetingMinutesExporter {
            let exporter: any ExportServiceProtocol
            init(exporter: any ExportServiceProtocol) {
                self.exporter = exporter
            }
            func export(meeting: Meeting) -> String {
                return exporter.generateMarkdown(for: meeting)
            }
        }
        
        let client = MeetingMinutesExporter(exporter: exportService)
        let output = client.export(meeting: sampleMeeting)
        XCTAssertTrue(output.contains("Sprint Review & Release"))
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Sparse Meetings, Incomplete Data)
    
    /// Tier 2: Feature 7 - Validates pdfGenerationFailed error typing and description.
    func test_tier2_feature7_pdfGenerationFailedError() throws {
        let error = ExportError.pdfGenerationFailed("CGContext allocation failed")
        XCTAssertEqual(error.errorDescription, "Failed to render PDF report: CGContext allocation failed")
    }
    
    /// Tier 2: Feature 7 - Validates emptyMeetingData error typing and description.
    func test_tier2_feature7_emptyMeetingDataError() throws {
        let error = ExportError.emptyMeetingData
        XCTAssertEqual(error.errorDescription, "Meeting does not contain sufficient data to export.")
    }
    
    /// Tier 2: Feature 7 - Validates fileWriteFailed error typing and description.
    func test_tier2_feature7_fileWriteFailedError() throws {
        let error = ExportError.fileWriteFailed("Disk write error")
        XCTAssertEqual(error.errorDescription, "Failed to write exported file: Disk write error")
    }
    
    /// Tier 2: Feature 7 - Validates export of sparse meeting with nil summary, 0 participants, 0 segments.
    func test_tier2_feature7_sparseMeetingExportSafe() throws {
        let sparseMeeting = Meeting(title: "Empty Sync")
        let md = exportService.generateMarkdown(for: sparseMeeting)
        
        XCTAssertTrue(md.contains("# Meeting Minutes: Empty Sync"))
        XCTAssertFalse(md.contains("## Attendees"))
        XCTAssertFalse(md.contains("## Executive Summary"))
        XCTAssertFalse(md.contains("## Action Items"))
        XCTAssertFalse(md.contains("## Transcript"))
    }
    
    /// Tier 2: Feature 7 - Validates sparse plain text export safe without nil crash.
    func test_tier2_feature7_sparsePlainTextExportSafe() throws {
        let sparseMeeting = Meeting(title: "Quick Check")
        let text = exportService.generatePlainText(for: sparseMeeting)
        
        XCTAssertTrue(text.contains("MEETMIND MINUTES: Quick Check"))
        XCTAssertFalse(text.contains("ATTENDEES:"))
        XCTAssertFalse(text.contains("EXECUTIVE SUMMARY:"))
    }
    
    /// Tier 2: Feature 7 - Validates uncompleted action items format as [ ] in markdown and plain text.
    func test_tier2_feature7_uncompletedActionItemMarkdownFormat() throws {
        let meeting = Meeting(title: "Task Review")
        meeting.addActionItem(ActionItem(title: "Draft release notes", isCompleted: false))
        
        let md = exportService.generateMarkdown(for: meeting)
        XCTAssertTrue(md.contains("- [ ] **Draft release notes**"))
        
        let plain = exportService.generatePlainText(for: meeting)
        XCTAssertTrue(plain.contains("[ ] Draft release notes"))
    }
    
    /// Tier 2: Feature 7 - Validates special markdown characters in title are rendered.
    func test_tier2_feature7_specialMarkdownCharactersInTitle() throws {
        let meeting = Meeting(title: "[Urgent] Meeting *Sync* #42")
        let md = exportService.generateMarkdown(for: meeting)
        XCTAssertTrue(md.contains("# Meeting Minutes: [Urgent] Meeting *Sync* #42"))
    }
    
    /// Tier 2: Feature 7 - Validates mockService throws configured error.
    func test_tier2_feature7_mockServiceThrowsConfiguredError() throws {
        mockService.shouldThrowError = .pdfGenerationFailed("Render cancelled")
        
        XCTAssertThrowsError(try mockService.generatePDFReport(for: sampleMeeting)) { error in
            XCTAssertEqual(error as? ExportError, .pdfGenerationFailed("Render cancelled"))
        }
    }
    
    // MARK: - Tier 3: Pairwise Value Types & Auditing
    
    /// Tier 3: Pairwise - Verifies mockService audits lastExportedMeeting.
    func test_tier3_lastExportedMeetingAuditing() throws {
        XCTAssertNil(mockService.lastExportedMeeting)
        _ = try mockService.generatePDFReport(for: sampleMeeting)
        XCTAssertEqual(mockService.lastExportedMeeting?.id, sampleMeeting.id)
    }
    
    /// Tier 3: Pairwise - Verifies ExportError Equatable conformance.
    func test_tier3_exportErrorEquatable() throws {
        let err1 = ExportError.pdfGenerationFailed("Memory error")
        let err2 = ExportError.pdfGenerationFailed("Memory error")
        let err3 = ExportError.emptyMeetingData
        
        XCTAssertEqual(err1, err2)
        XCTAssertNotEqual(err1, err3)
    }
    
    /// Tier 1: Feature 7 - Validates markdown export with multiple speakers.
    func test_tier1_feature7_generateMarkdownWithMultipleSpeakers() throws {
        let speaker2 = Speaker(name: "Bob Rivera", role: "Architect")
        sampleMeeting.addParticipant(speaker2)
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("Bob Rivera (Architect)"))
    }
    
    /// Tier 1: Feature 7 - Validates markdown export with high priority action item.
    func test_tier1_feature7_generateMarkdownWithHighPriorityActionItem() throws {
        let highItem = ActionItem(title: "Urgent fix", isCompleted: false, priority: .high)
        sampleMeeting.addActionItem(highItem)
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("[Priority: High]"))
    }
    
    /// Tier 1: Feature 7 - Validates plain text export with multiple attendees.
    func test_tier1_feature7_generatePlainTextWithMultipleAttendees() throws {
        let speaker2 = Speaker(name: "Bob Rivera", role: "Architect")
        sampleMeeting.addParticipant(speaker2)
        let text = exportService.generatePlainText(for: sampleMeeting)
        XCTAssertTrue(text.contains("Bob Rivera"))
    }
    
    /// Tier 2: Feature 7 - Validates export of meeting with multiple action items.
    func test_tier2_feature7_exportMeetingWithMultipleActionItems() throws {
        sampleMeeting.addActionItem(ActionItem(title: "Task A", isCompleted: true))
        sampleMeeting.addActionItem(ActionItem(title: "Task B", isCompleted: false))
        let md = exportService.generateMarkdown(for: sampleMeeting)
        XCTAssertTrue(md.contains("- [x] **Task A**"))
        XCTAssertTrue(md.contains("- [ ] **Task B**"))
    }
    
    /// Tier 2: Feature 7 - Validates export plain text contains formatted date.
    func test_tier2_feature7_exportPlainTextContainsFormattedDate() throws {
        let text = exportService.generatePlainText(for: sampleMeeting)
        XCTAssertTrue(text.contains("Date:"))
    }
    
    /// Tier 3: Pairwise - Verifies custom PDF mock data return.
    func test_tier3_mockExportServiceCustomDataReturn() throws {
        let customData = "%PDF-1.7 CUSTOM DATA".data(using: .utf8)!
        mockService.mockPDFData = customData
        let data = try mockService.generatePDFReport(for: sampleMeeting)
        XCTAssertEqual(data, customData)
    }
}
