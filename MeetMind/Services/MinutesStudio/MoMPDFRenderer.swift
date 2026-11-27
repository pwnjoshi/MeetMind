import UIKit

/// Draws a `MoMDocumentModel` into a paginated A4 PDF. The same value drives the on-screen document.
enum MoMPDFRenderer {
    private static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48

    @MainActor
    static func render(document: MoMDocumentModel, letterhead: UIImage?, logo: UIImage?) -> Data {
        let page = pageSize
        let margin = Self.margin
        let width = page.width - margin * 2
        let bottom = page.height - margin
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
                ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: options, context: nil).height)
            }

            func attributed(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> NSAttributedString {
                NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: color
                ])
            }

            func ensure(_ needed: CGFloat) {
                if y + needed > bottom {
                    context.beginPage()
                    y = margin
                }
            }

            func text(_ string: String, size: CGFloat = 11, weight: UIFont.Weight = .regular,
                      color: UIColor = .black, indent: CGFloat = 0, after: CGFloat = 4) {
                guard !string.isEmpty else { return }
                let value = attributed(string, size: size, weight: weight, color: color)
                let h = height(of: value, width: width - indent)
                ensure(h)
                value.draw(with: CGRect(x: margin + indent, y: y, width: width - indent, height: h),
                           options: options, context: nil)
                y += h + after
            }

            func row(_ cells: [(String, CGFloat)], weight: UIFont.Weight = .regular, color: UIColor = .black) {
                var maxHeight: CGFloat = 0
                let values = cells.map { attributed($0.0, size: 10, weight: weight, color: color) }
                for (index, value) in values.enumerated() {
                    maxHeight = max(maxHeight, height(of: value, width: cells[index].1 * width - 6))
                }
                ensure(maxHeight + 6)
                var x = margin
                for (index, value) in values.enumerated() {
                    let w = cells[index].1 * width
                    value.draw(with: CGRect(x: x, y: y, width: w - 6, height: maxHeight), options: options, context: nil)
                    x += w
                }
                y += maxHeight + 6
            }

            func section(_ title: String) {
                y += 8
                ensure(30)
                text(title, size: 14, weight: .bold, after: 6)
            }

            if let letterhead {
                let ratio = letterhead.size.height / max(letterhead.size.width, 1)
                let h = min(width * ratio, 90)
                letterhead.draw(in: CGRect(x: margin, y: y, width: width, height: h))
                y += h + 12
            } else if let logo {
                logo.draw(in: CGRect(x: margin, y: y, width: 32, height: 32))
                y += 40
            }

            text("MINUTES OF MEETING", size: 10, weight: .semibold, color: UIColor(red: 0.31, green: 0.27, blue: 0.9, alpha: 1))
            text(document.reference, size: 10, color: .darkGray, after: 6)
            text(document.title, size: 22, weight: .bold, after: 4)
            text(document.subtitle, size: 11, color: .darkGray)
            text(document.status.text, size: 10, weight: .semibold, color: .darkGray, after: 10)

            row([("Date", 0.25), (document.dateText, 0.75)])
            row([("Time", 0.25), (document.timeText, 0.75)])
            if let venue = document.venue, !venue.isEmpty { row([("Venue", 0.25), (venue, 0.75)]) }
            if let chair = document.chairperson { row([("Chairperson", 0.25), (chair, 0.75)]) }
            if let by = document.minutesBy { row([("Minutes by", 0.25), (by, 0.75)]) }

            section("1. Attendance")
            if let quorum = document.quorumText { text(quorum, size: 11, weight: .semibold) }
            for person in document.present { row([(person.name, 0.6), (person.trailing, 0.4)]) }
            if !document.invitees.isEmpty { text("In attendance (invitee)", size: 10, weight: .semibold, color: .darkGray) }
            for person in document.invitees { row([(person.name, 0.6), (person.trailing, 0.4)]) }
            if !document.leave.isEmpty { text("Leave of absence", size: 10, weight: .semibold, color: .darkGray) }
            for person in document.leave { row([(person.name, 0.6), (person.trailing, 0.4)]) }

            section("2. Previous Minutes")
            text(document.previous.text)

            section("3. Agenda and Discussion")
            for (index, topic) in document.topics.enumerated() {
                text("3.\(index + 1)  \(topic.title)", size: 12, weight: .semibold, after: 3)
                for bullet in topic.discussion { text("\u{2022} \(bullet)", indent: 10, after: 2) }
                if topic.hasOutcome {
                    var label = topic.outcomeKind.label
                    if let chip = topic.sourceChipText { label += "  (\(chip))" }
                    text(label, size: 9, weight: .bold, color: outcomeColor(topic.outcomeKind), indent: 10, after: 1)
                    text(topic.outcomeText, size: 11, weight: .medium, indent: 10, after: 8)
                }
            }

            section("4. Action Taken Report")
            if document.actions.isEmpty {
                text("No actions were recorded.")
            } else {
                row([("#", 0.06), ("Action", 0.5), ("By", 0.18), ("Target", 0.14), ("Status", 0.12)],
                    weight: .semibold, color: .darkGray)
                for action in document.actions {
                    row([("\(action.number)", 0.06), (action.title, 0.5), (action.by, 0.18),
                         (action.target, 0.14), (action.isDone ? "Done" : "Open", 0.12)])
                }
            }

            section("5. Any Other Business")
            text(document.anyOtherBusiness)
            section("6. Next Meeting")
            if let next = document.nextMeetingText { text(next, weight: .semibold) }
            if let note = document.nextMeetingNote { text(note) }
            if document.nextMeetingText == nil && document.nextMeetingNote == nil { text("Not scheduled.") }
            section("7. Closure")
            text(document.closure.isEmpty ? "Not recorded." : document.closure)

            section("8. Sign-off")
            ensure(110)
            if let data = document.signOff.signaturePNG, let image = UIImage(data: data) {
                let ratio = image.size.width / max(image.size.height, 1)
                let h: CGFloat = 60
                image.draw(in: CGRect(x: margin, y: y, width: min(h * ratio, 220), height: h))
                y += h + 4
            } else {
                y += 40
            }
            text(document.signOff.name, size: 12, weight: .semibold, after: 1)
            text(document.signOff.role, size: 10, color: .darkGray, after: 1)
            if let date = document.signOff.signedAt {
                text("Date of signing: \(MoMDocumentBuilder.longDate(date))", size: 10, color: .darkGray, after: 1)
            }
            if let place = document.signOff.place, !place.isEmpty {
                text("Place: \(place)", size: 10, color: .darkGray, after: 6)
            }
            text(document.signOff.recordedBy, size: 9, color: .gray)
        }
    }

    private static func outcomeColor(_ kind: MoMOutcomeKind) -> UIColor {
        switch kind {
        case .resolved: return UIColor(red: 0.13, green: 0.55, blue: 0.3, alpha: 1)
        case .deferred: return UIColor(red: 0.85, green: 0.5, blue: 0.1, alpha: 1)
        case .open: return .darkGray
        }
    }

    @MainActor
    static func writeTemporaryPDF(document: MoMDocumentModel, letterhead: UIImage?, logo: UIImage?) throws -> URL {
        let data = render(document: document, letterhead: letterhead, logo: logo)
        guard data.starts(with: Data("%PDF-".utf8)) else { throw ExportError.pdfGenerationFailed("The generated file is not a PDF document.") }
        let safe = document.reference.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
