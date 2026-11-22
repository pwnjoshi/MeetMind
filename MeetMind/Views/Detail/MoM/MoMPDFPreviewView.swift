import SwiftUI
import PDFKit
import UIKit

struct MoMPDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// PDF preview of the same document model that the screen shows (Figma B6b). Share goes through the
/// share flow so the animated outcome screens are reached; Print uses the system print sheet.
@MainActor
struct MoMPDFPreviewView: View {
    let document: MoMDocumentModel
    let onShare: (URL) -> Void
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let pdfURL {
                MoMPDFKitView(url: pdfURL)
            } else if let errorMessage {
                ContentUnavailableView("PDF Unavailable", systemImage: "doc.badge.exclamationmark",
                                       description: Text(errorMessage))
            } else {
                ProgressView("Preparing PDF\u{2026}")
            }
        }
        .navigationTitle("PDF Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Print", systemImage: "printer") { printPDF() }
                    .disabled(pdfURL == nil)
                Button("Share", systemImage: "square.and.arrow.up") {
                    if let pdfURL { onShare(pdfURL) }
                }
                .disabled(pdfURL == nil)
            }
        }
        .task(id: document) { render() }
    }

    private func render() {
        do {
            let logo = UIImage(named: "ManentLogo")
            pdfURL = try MoMPDFRenderer.writeTemporaryPDF(document: document, letterhead: nil, logo: logo)
            errorMessage = nil
        } catch {
            pdfURL = nil
            errorMessage = error.localizedDescription
        }
    }

    private func printPDF() {
        guard let pdfURL, UIPrintInteractionController.canPrint(pdfURL) else {
            errorMessage = "This PDF cannot be printed."
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = document.reference
        controller.printInfo = info
        controller.printingItem = pdfURL
        controller.present(animated: true)
    }
}
