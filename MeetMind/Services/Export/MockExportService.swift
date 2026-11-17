import Foundation

public final class MockExportService: ExportServiceProtocol, @unchecked Sendable {
    public var mockPDFData: Data
    public var mockMarkdown: String
    public var mockPlainText: String
    public var shouldThrowError: ExportError? = nil
    public var lastExportedMeeting: Meeting? = nil
    
    public init() {
        self.mockPDFData = "%PDF-1.4\n1 0 obj\n<< /Title (MeetMind Report) >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF".data(using: .utf8) ?? Data()
        self.mockMarkdown = "# Meeting Minutes\n\n**Date**: Today\n\n## Summary\nExecutive summary content.\n"
        self.mockPlainText = "MEETMIND MINUTES\nDate: Today\nSummary: Executive summary content.\n"
    }
    
    public func generatePDFReport(for meeting: Meeting) throws -> Data {
        lastExportedMeeting = meeting
        if let error = shouldThrowError {
            throw error
        }
        return mockPDFData
    }
    
    public func generateMarkdown(for meeting: Meeting) -> String {
        lastExportedMeeting = meeting
        return mockMarkdown
    }
    
    public func generatePlainText(for meeting: Meeting) -> String {
        lastExportedMeeting = meeting
        return mockPlainText
    }
}
