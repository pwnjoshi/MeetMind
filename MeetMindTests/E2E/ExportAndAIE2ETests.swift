import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class ExportAndAIE2ETests: XCTestCase {
    func testLocalSummaryCanBeExportedAsPDFAndMarkdown() async throws {
        let meeting = Meeting(title: "Release review", status: .completed)
        let response = try await NaturalLanguageSummarizationService().generateSummary(from: "We approved the release. Alice will run the device test tomorrow.")
        meeting.summary = Summary(executiveSummary: response.executiveSummary, keyPoints: response.keyDiscussionPoints, keyDecisions: response.keyDecisions)
        let export = ExportService()
        let pdf = try export.generatePDFReport(for: meeting)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(pdf.count, 100)
        let detail = MeetingDetailViewModel(meeting: meeting, exportService: export)
        XCTAssertTrue(detail.exportMarkdown().contains("Release review"))
    }
    func testEmptyTranscriptCannotProduceInventedSummary() async {
        do {
            _ = try await NaturalLanguageSummarizationService().generateSummary(from: "   ")
            XCTFail("An empty transcript must fail")
        } catch { XCTAssertEqual(error as? SummarizationError, .emptyTranscript) }
    }
}
