import Foundation
import UIKit
import PDFKit

/// Immutable reviewed content used by PDF, Markdown, plain-text sharing, and approval.
public struct DocumentSnapshot: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let heading: String
        public let lines: [String]
    }

    public struct Action: Equatable, Sendable {
        public let title: String
        public let assignee: String
        public let dueDate: String?
        public let priority: String
        public let isCompleted: Bool
    }

    public struct TranscriptLine: Equatable, Sendable {
        public let speaker: String
        public let timestamp: String
        public let text: String
    }

    public let meetingID: UUID
    public let title: String
    public let formattedDate: String
    public let formattedDuration: String
    public let status: String
    public let sections: [Section]
    public let actions: [Action]
    /// Sections printed after the action items.
    public let closingSections: [Section]
    public let transcript: [TranscriptLine]

    /// Builds the snapshot from the same categorized content the Minutes tab shows.
    /// Suggested tasks that were not accepted are not part of the minutes and are never exported.
    /// `record` carries the decided-by metadata; when nil the shared record store is read (main thread only).
    public static func make(from meeting: Meeting, record: MeetingRecordData? = nil) -> Self {
        let resolved = record ?? currentRecord(for: meeting.id)
        let content = MeetingMinutesContent.make(from: meeting, record: resolved)
        return make(from: meeting, content: content)
    }

    static func make(from meeting: Meeting, content: MeetingMinutesContent) -> Self {
        let presentHeading = content.hasAttendanceRecord ? "Present" : "Attendees"
        let candidates: [Section] = [
            Section(heading: "Executive Summary", lines: content.summary.isEmpty ? [] : [content.summary]),
            Section(heading: "Agenda", lines: content.agenda),
            Section(heading: presentHeading, lines: content.present.map(\.label)),
            Section(heading: "Absent", lines: content.absent.map(\.label)),
            Section(heading: "Key Decisions", lines: content.decisions.map { content.decisionLine($0) })
        ]
        let sections = candidates.filter { !$0.lines.isEmpty }
        let actions = content.actions.map { line in
            Action(title: line.title, assignee: line.ownerName, dueDate: line.dueText,
                   priority: line.priorityName, isCompleted: line.isCompleted)
        }
        let transcript = meeting.orderedTranscriptSegments.map {
            TranscriptLine(speaker: $0.speakerDisplayName, timestamp: $0.formattedStartTime, text: $0.text)
        }
        return Self(
            meetingID: meeting.id,
            title: meeting.title,
            formattedDate: meeting.formattedDate,
            formattedDuration: meeting.formattedDuration,
            status: meeting.status.displayName,
            sections: sections,
            actions: actions,
            closingSections: [],
            transcript: transcript
        )
    }

    /// The same document without the transcript, for email bodies and the clipboard.
    public func withoutTranscript() -> Self {
        Self(meetingID: meetingID, title: title, formattedDate: formattedDate, formattedDuration: formattedDuration,
             status: status, sections: sections, actions: actions, closingSections: closingSections, transcript: [])
    }

    private static func currentRecord(for meetingID: UUID) -> MeetingRecordData {
        guard Thread.isMainThread else { return MeetingRecordData() }
        return MainActor.assumeIsolated { MeetingRecordStore.shared.record(for: meetingID) }
    }
}

public final class ExportService: ExportServiceProtocol, @unchecked Sendable {
    private let pdfRenderer: (DocumentSnapshot) throws -> Data

    public init() {
        pdfRenderer = Self.renderPDF
    }

    /// Renderer injection makes failure behavior deterministic in tests.
    init(pdfRenderer: @escaping (DocumentSnapshot) throws -> Data) {
        self.pdfRenderer = pdfRenderer
    }

    public func generatePDFReport(for meeting: Meeting) throws -> Data {
        try generatePDFReport(snapshot: .make(from: meeting))
    }

    public func generatePDFReport(snapshot: DocumentSnapshot) throws -> Data {
        let data: Data
        do { data = try pdfRenderer(snapshot) }
        catch let error as ExportError { throw error }
        catch { throw ExportError.pdfGenerationFailed(error.localizedDescription) }
        guard data.starts(with: Data("%PDF-".utf8)), data.count > 20,
              let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ExportError.pdfGenerationFailed("The renderer did not produce a valid PDF document.")
        }
        return data
    }

    private static func renderPDF(_ snapshot: DocumentSnapshot) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let contentWidth = pageRect.width - margin * 2
        let maxContentY = pageRect.height - margin
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: snapshot.title,
            kCGPDFContextAuthor as String: "Manent",
            kCGPDFContextCreator as String: "Manent iOS"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            var pageIndex = 1
            var currentY = margin

            func startNewPage() {
                context.beginPage()
                currentY = margin
                let footer = "Manent  |  \(snapshot.title)  |  Page \(pageIndex)"
                footer.draw(in: CGRect(x: margin, y: pageRect.height - 28, width: contentWidth, height: 12),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.systemGray])
                pageIndex += 1
            }

            func drawSection(_ heading: String, lines: [String], color: UIColor = .systemBlue) {
                if currentY + 44 > maxContentY { startNewPage() }
                heading.uppercased().draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: color])
                currentY += 16
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black]
                for line in lines {
                    let height = ceil(line.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil).height) + 4
                    if currentY + height > maxContentY { startNewPage() }
                    line.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: height), withAttributes: attributes)
                    currentY += height
                }
                currentY += 10
            }

            startNewPage()
            "MANENT MINUTES".draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor.darkGray])
            currentY += 16
            snapshot.title.draw(in: CGRect(x: margin, y: currentY, width: contentWidth, height: 40), withAttributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.black])
            currentY += 36
            let metadata = "Date: \(snapshot.formattedDate)  •  Duration: \(snapshot.formattedDuration)  •  Status: \(snapshot.status)"
            metadata.draw(at: CGPoint(x: margin, y: currentY), withAttributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.darkGray])
            currentY += 24
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.move(to: CGPoint(x: margin, y: currentY))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: currentY))
            context.cgContext.strokePath()
            currentY += 16

            for section in snapshot.sections { drawSection(section.heading, lines: section.lines) }
            if !snapshot.actions.isEmpty {
                drawSection("Action Items (\(snapshot.actions.count))", lines: snapshot.actions.map {
                    "\($0.isCompleted ? "[X]" : "[  ]")  \($0.title)  (\($0.assignee))  [Priority: \($0.priority)]"
                }, color: .systemGreen)
            }
            for section in snapshot.closingSections { drawSection(section.heading, lines: section.lines) }
            if !snapshot.transcript.isEmpty {
                drawSection("Transcript", lines: snapshot.transcript.map {
                    "\($0.speaker) [\($0.timestamp)]:\n\($0.text)"
                }, color: .darkGray)
            }
        }
    }

    public func generateMarkdown(for meeting: Meeting) -> String {
        generateMarkdown(snapshot: .make(from: meeting))
    }

    public func generateMarkdown(snapshot: DocumentSnapshot) -> String {
        var text = "# Meeting Minutes: \(snapshot.title)\n\n"
        text += "**Date**: \(snapshot.formattedDate)  \n"
        text += "**Duration**: \(snapshot.formattedDuration)  \n"
        text += "**Status**: \(snapshot.status)  \n\n"
        for section in snapshot.sections {
            text += "## \(section.heading)\n"
            text += section.lines.map { "- \($0)\n" }.joined()
            text += "\n"
        }
        if !snapshot.actions.isEmpty {
            text += "## Action Items\n"
            for action in snapshot.actions {
                let due = action.dueDate.map { " (Due: \($0))" } ?? ""
                text += "- [\(action.isCompleted ? "x" : " ")] **\(action.title)** - \(action.assignee)\(due) [Priority: \(action.priority)]\n"
            }
            text += "\n"
        }
        for section in snapshot.closingSections {
            text += "## \(section.heading)\n"
            text += section.lines.map { "- \($0)\n" }.joined()
            text += "\n"
        }
        if !snapshot.transcript.isEmpty {
            text += "## Transcript\n"
            for line in snapshot.transcript {
                text += "**\(line.speaker)** [\(line.timestamp)]: \(line.text)\n\n"
            }
        }
        return text
    }

    public func generatePlainText(for meeting: Meeting) -> String {
        generatePlainText(snapshot: .make(from: meeting))
    }

    public func generatePlainText(snapshot: DocumentSnapshot) -> String {
        var text = "MANENT MINUTES: \(snapshot.title)\n========================================\n"
        text += "Date: \(snapshot.formattedDate)\nDuration: \(snapshot.formattedDuration)\nStatus: \(snapshot.status)\n\n"
        for section in snapshot.sections {
            text += "\(section.heading.uppercased()):\n"
            text += section.lines.map { "• \($0)\n" }.joined()
            text += "\n"
        }
        if !snapshot.actions.isEmpty {
            text += "ACTION ITEMS:\n"
            for action in snapshot.actions {
                let due = action.dueDate.map { " (Due: \($0))" } ?? ""
                text += "[\(action.isCompleted ? "X" : " ")] \(action.title) (\(action.assignee))\(due) [\(action.priority)]\n"
            }
            text += "\n"
        }
        for section in snapshot.closingSections {
            text += "\(section.heading.uppercased()):\n"
            text += section.lines.map { "• \($0)\n" }.joined()
            text += "\n"
        }
        if !snapshot.transcript.isEmpty {
            text += "TRANSCRIPT:\n"
            for line in snapshot.transcript {
                text += "\(line.speaker) [\(line.timestamp)]: \(line.text)\n\n"
            }
        }
        return text
    }
}
