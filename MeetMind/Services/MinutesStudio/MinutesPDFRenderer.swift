import UIKit
import PDFKit

/// Loads a user-supplied letterhead (image or PDF) from the local store.
enum MinutesLetterheadLoader {
    /// For PDFs the top 18% of the first page is used, since letterheads sit at the top of the page.
    @MainActor
    static func image(for letterhead: MinutesCustomLetterhead, store: MinutesStudioStore) -> UIImage? {
        let url = store.letterheadFileURL(letterhead)
        if !letterhead.isPDF {
            return UIImage(contentsOfFile: url.path)
        }
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let width: CGFloat = 1000
        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        let full = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = full.cgImage else { return full }
        let cropRect = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height) * 0.18)
        guard let cropped = cgImage.cropping(to: cropRect) else { return full }
        return UIImage(cgImage: cropped, scale: full.scale, orientation: .up)
    }
}

/// Draws a `MinutesDocument` into a paginated A4 PDF. Runs only when the user opens the
/// preview or shares the document.
enum MinutesPDFRenderer {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48

    @MainActor
    static func render(document: MinutesDocument, letterhead: UIImage?) -> Data {
        let page = pageSize
        let margin = Self.margin
        let contentWidth = page.width - margin * 2
        let maxHeight = page.height - margin * 2
        let drawOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            func drawText(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment, after: CGFloat) {
                guard !text.isEmpty else { return }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = .byWordWrapping
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ])
                let bounding = attributed.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: drawOptions,
                    context: nil
                )
                let height = min(ceil(bounding.height), maxHeight)
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
                attributed.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: height), options: drawOptions, context: nil)
                y += height + after
            }

            if let letterhead, letterhead.size.width > 0, letterhead.size.height > 0 {
                let scale = min(contentWidth / letterhead.size.width, 90 / letterhead.size.height)
                let drawSize = CGSize(width: letterhead.size.width * scale, height: letterhead.size.height * scale)
                letterhead.draw(in: CGRect(x: margin, y: y, width: drawSize.width, height: drawSize.height))
                y += drawSize.height + 12
            }

            let headerAlignment: NSTextAlignment = document.headerCentered ? .center : .left
            for (index, line) in document.headerLines.enumerated() {
                drawText(line, size: index == 0 ? 16 : 11, weight: index == 0 ? .bold : .regular, color: .black, alignment: headerAlignment, after: 2)
            }
            if !document.headerLines.isEmpty { y += 10 }

            drawText(document.statusLabel, size: 10, weight: .regular, color: .darkGray, alignment: .left, after: 4)
            drawText(document.setupLine, size: 10, weight: .regular, color: .darkGray, alignment: .left, after: 12)
            drawText(document.heading, size: 20, weight: .bold, color: .black, alignment: .left, after: 8)
            drawText(document.title, size: 16, weight: .semibold, color: .black, alignment: .left, after: 6)
            drawText(document.dateLine, size: 11, weight: .regular, color: .darkGray, alignment: .left, after: 4)
            drawText(document.typeLine, size: 11, weight: .regular, color: .darkGray, alignment: .left, after: 16)

            for block in document.blocks {
                switch block.style {
                case .heading:
                    drawText(block.heading, size: 14, weight: .semibold, color: .black, alignment: .left, after: 4)
                    for line in block.lines {
                        drawText(line, size: 12, weight: .regular, color: .black, alignment: .left, after: 3)
                    }
                case .caption:
                    drawText(block.heading, size: 11, weight: .regular, color: .darkGray, alignment: .left, after: 3)
                    for line in block.lines {
                        drawText(line, size: 11, weight: .regular, color: .black, alignment: .left, after: 2)
                    }
                }
                y += 12
            }
        }
    }

    /// Writes the PDF to the temporary directory for ShareLink.
    @MainActor
    static func writeTemporaryPDF(document: MinutesDocument, letterhead: UIImage?) -> URL? {
        let data = render(document: document, letterhead: letterhead)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let base = document.title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = "Minutes - \(base.isEmpty ? "Meeting" : base).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
