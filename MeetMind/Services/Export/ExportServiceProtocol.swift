import Foundation

/// Errors thrown by the export service
public enum ExportError: LocalizedError, Sendable, Equatable {
    case pdfGenerationFailed(String)
    case emptyMeetingData
    case fileWriteFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed(let reason):
            return "Failed to render PDF report: \(reason)"
        case .emptyMeetingData:
            return "Meeting does not contain sufficient data to export."
        case .fileWriteFailed(let reason):
            return "Failed to write exported file: \(reason)"
        }
    }
}

/// Protocol defining export capabilities for meeting minutes
public protocol ExportServiceProtocol: AnyObject, Sendable {
    /// Generates a multi-page PDF report containing branded headers, summary, action items, and transcript
    func generatePDFReport(for meeting: Meeting) throws -> Data
    
    /// Generates CommonMark formatted Markdown text for export or note apps
    func generateMarkdown(for meeting: Meeting) -> String
    
    /// Generates clean plain text suitable for email sharing or clipboard copying
    func generatePlainText(for meeting: Meeting) -> String
}
