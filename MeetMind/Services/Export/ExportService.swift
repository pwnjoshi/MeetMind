import Foundation
import UIKit

public final class ExportService: ExportServiceProtocol, @unchecked Sendable {
    public init() {}
    
    public func generatePDFReport(for meeting: Meeting) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Standard US Letter
        let margin: CGFloat = 40.0
        let contentWidth = pageRect.width - (margin * 2)
        let maxContentY = pageRect.height - margin
        
        let format = UIGraphicsPDFRendererFormat()
        let metadata: [String: Any] = [
            kCGPDFContextTitle as String: meeting.title,
            kCGPDFContextAuthor as String: "MeetMind Intelligence",
            kCGPDFContextCreator as String: "MeetMind iOS"
        ]
        format.documentInfo = metadata
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let pdfData = renderer.pdfData { context in
            var pageIndex = 1
            var currentY: CGFloat = margin
            
            func startNewPage() {
                context.beginPage()
                currentY = margin
                
                // Draw running page footer
                let footerText = "MeetMind  |  \(meeting.title)  |  Page \(pageIndex)"
                let footerAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.systemGray
                ]
                let footerSize = footerText.size(withAttributes: footerAttributes)
                let footerRect = CGRect(x: margin, y: pageRect.height - 28, width: contentWidth, height: footerSize.height)
                footerText.draw(in: footerRect, withAttributes: footerAttributes)
                pageIndex += 1
            }
            
            startNewPage()
            
            // 1. Header Banner
            let appName = "MEETMIND MINUTES"
            let appAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: UIColor(red: 0.12, green: 0.18, blue: 0.16, alpha: 1.0)
            ]
            appName.draw(at: CGPoint(x: margin, y: currentY), withAttributes: appAttrs)
            currentY += 16
            
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let titleRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 40)
            meeting.title.draw(in: titleRect, withAttributes: titleAttrs)
            currentY += 36
            
            // 2. Metadata: Date, Duration, Status
            let metaString = "Date: \(meeting.formattedDate)  •  Duration: \(meeting.formattedDuration)  •  Status: \(meeting.status.displayName)"
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            metaString.draw(at: CGPoint(x: margin, y: currentY), withAttributes: metaAttrs)
            currentY += 24
            
            // Divider line
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.setLineWidth(1.0)
            context.cgContext.move(to: CGPoint(x: margin, y: currentY))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: currentY))
            context.cgContext.strokePath()
            currentY += 16
            
            // 3. Attendees Section
            if !meeting.participants.isEmpty {
                let attTitle = "ATTENDEES"
                let secAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)
                ]
                attTitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: secAttrs)
                currentY += 16
                
                let attendeeList = meeting.participants.map { $0.displayLabel }.joined(separator: ", ")
                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                let attRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 30)
                attendeeList.draw(in: attRect, withAttributes: bodyAttrs)
                currentY += 26
            }
            
            // 4. Executive Summary Section
            if let summary = meeting.summary, !summary.executiveSummary.isEmpty {
                if currentY + 100 > maxContentY { startNewPage() }
                
                let sumTitle = "EXECUTIVE SUMMARY"
                let sumAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
                ]
                sumTitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: sumAttrs)
                currentY += 16
                
                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor.black
                ]
                let sumBounding = summary.executiveSummary.boundingRect(
                    with: CGSize(width: contentWidth - 16, height: 1000),
                    options: .usesLineFragmentOrigin,
                    attributes: bodyAttrs,
                    context: nil
                )
                
                // Draw background callout box
                let boxRect = CGRect(x: margin, y: currentY, width: contentWidth, height: sumBounding.height + 16)
                context.cgContext.setFillColor(UIColor(white: 0.96, alpha: 1.0).cgColor)
                context.cgContext.fill(boxRect)
                
                summary.executiveSummary.draw(
                    in: CGRect(x: margin + 8, y: currentY + 8, width: contentWidth - 16, height: sumBounding.height),
                    withAttributes: bodyAttrs
                )
                currentY += sumBounding.height + 26
            }
            
            // 5. Action Items Section
            if !meeting.actionItems.isEmpty {
                if currentY + 80 > maxContentY { startNewPage() }
                
                let actTitle = "ACTION ITEMS (\(meeting.actionItems.count))"
                let actAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1.0)
                ]
                actTitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: actAttrs)
                currentY += 18
                
                for item in meeting.actionItems {
                    if currentY + 30 > maxContentY { startNewPage() }
                    
                    let checkMark = item.isCompleted ? "[X]" : "[  ]"
                    let line = "\(checkMark)  \(item.title)  (\(item.assigneeName))  [Priority: \(item.priority.displayName)]"
                    let itemAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: item.isCompleted ? UIColor.gray : UIColor.black
                    ]
                    line.draw(at: CGPoint(x: margin, y: currentY), withAttributes: itemAttrs)
                    currentY += 18
                }
                currentY += 12
            }
            
            // 6. Diarized Transcript Section
            if !meeting.transcriptSegments.isEmpty {
                if currentY + 80 > maxContentY { startNewPage() }
                
                let transTitle = "TRANSCRIPT"
                let tAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor(red: 0.12, green: 0.18, blue: 0.16, alpha: 1.0)
                ]
                transTitle.draw(at: CGPoint(x: margin, y: currentY), withAttributes: tAttrs)
                currentY += 18
                
                let sortedSegments = meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }
                for segment in sortedSegments {
                    let textAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: UIColor.black
                    ]
                    let textBounding = segment.text.boundingRect(
                        with: CGSize(width: contentWidth, height: 1000),
                        options: .usesLineFragmentOrigin,
                        attributes: textAttrs,
                        context: nil
                    )
                    let textHeight = ceil(textBounding.height)
                    let headerHeight: CGFloat = 14
                    let segmentSpacing: CGFloat = 10
                    
                    // Pre-check bounding box: advance to a new page whenever currentY + textHeight + headerHeight > maxContentY
                    if currentY + headerHeight + textHeight + segmentSpacing > maxContentY {
                        startNewPage()
                    }
                    
                    let speakerLabel = "\(segment.speakerDisplayName) [\(segment.formattedStartTime)]:"
                    let labelAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)
                    ]
                    speakerLabel.draw(at: CGPoint(x: margin, y: currentY), withAttributes: labelAttrs)
                    currentY += headerHeight
                    
                    segment.text.draw(
                        in: CGRect(x: margin, y: currentY, width: contentWidth, height: textHeight),
                        withAttributes: textAttrs
                    )
                    currentY += textHeight + segmentSpacing
                }
            }
        }
        
        return pdfData
    }
    
    public func generateMarkdown(for meeting: Meeting) -> String {
        var md = "# Meeting Minutes: \(meeting.title)\n\n"
        md += "**Date**: \(meeting.formattedDate)  \n"
        md += "**Duration**: \(meeting.formattedDuration)  \n"
        md += "**Status**: \(meeting.status.displayName)  \n\n"
        
        if !meeting.participants.isEmpty {
            md += "## Attendees\n"
            for participant in meeting.participants {
                md += "- \(participant.displayLabel)\n"
            }
            md += "\n"
        }
        
        if let summary = meeting.summary {
            md += "## Executive Summary\n\(summary.executiveSummary)\n\n"
            
            if !summary.keyDecisions.isEmpty {
                md += "## Key Decisions\n"
                for decision in summary.keyDecisions {
                    md += "- \(decision)\n"
                }
                md += "\n"
            }
        }
        
        if !meeting.actionItems.isEmpty {
            md += "## Action Items\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "[x]" : "[ ]"
                let due = item.formattedDueDate != nil ? " (Due: \(item.formattedDueDate ?? ""))" : ""
                md += "- \(check) **\(item.title)** - \(item.assigneeName)\(due) [Priority: \(item.priority.displayName)]\n"
            }
            md += "\n"
        }
        
        if !meeting.transcriptSegments.isEmpty {
            md += "## Transcript\n"
            let sortedSegments = meeting.transcriptSegments.sorted { $0.startTime < $1.startTime }
            for segment in sortedSegments {
                md += "**\(segment.speakerDisplayName)** [\(segment.formattedStartTime)]: \(segment.text)\n\n"
            }
        }
        
        return md
    }
    
    public func generatePlainText(for meeting: Meeting) -> String {
        var text = "MEETMIND MINUTES: \(meeting.title)\n"
        text += "========================================\n"
        text += "Date: \(meeting.formattedDate)\n"
        text += "Duration: \(meeting.formattedDuration)\n"
        text += "Status: \(meeting.status.displayName)\n\n"
        
        if !meeting.participants.isEmpty {
            text += "ATTENDEES:\n"
            for participant in meeting.participants {
                text += "• \(participant.displayLabel)\n"
            }
            text += "\n"
        }
        
        if let summary = meeting.summary {
            text += "EXECUTIVE SUMMARY:\n\(summary.executiveSummary)\n\n"
            if !summary.keyDecisions.isEmpty {
                text += "KEY DECISIONS:\n"
                for decision in summary.keyDecisions {
                    text += "• \(decision)\n"
                }
                text += "\n"
            }
        }
        
        if !meeting.actionItems.isEmpty {
            text += "ACTION ITEMS:\n"
            for item in meeting.actionItems {
                let mark = item.isCompleted ? "[X]" : "[ ]"
                text += "\(mark) \(item.title) (\(item.assigneeName)) [\(item.priority.displayName)]\n"
            }
            text += "\n"
        }
        
        return text
    }
}
