import SwiftUI
import UIKit

// MARK: - Document card

struct MinutesDocumentCardView: View {
    let document: MinutesDocument
    let letterheadImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let letterheadImage {
                Image(uiImage: letterheadImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .leading)
                    .accessibilityLabel("Letterhead")
            }
            if !document.headerLines.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(document.headerLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(index == 0 ? .headline : .caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: document.headerCentered ? .center : .leading)
                .multilineTextAlignment(document.headerCentered ? .center : .leading)
            }

            Text(document.statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(document.setupLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(document.heading)
                .font(.title3.weight(.bold))
                .padding(.top, 4)
            Text(document.title)
                .font(.headline)
            Text(document.dateLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(document.typeLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(document.blocks) { block in
                VStack(alignment: .leading, spacing: 4) {
                    switch block.style {
                    case .heading:
                        Text(block.heading)
                            .font(.headline)
                        ForEach(Array(block.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.subheadline)
                        }
                    case .caption:
                        Text(block.heading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(block.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview page (169:768)

@MainActor
struct MinutesDocumentPreviewView: View {
    let model: MinutesStudioModel
    @State private var pdfURL: URL?

    private struct RenderKey: Equatable {
        let document: MinutesDocument
        let letterheadID: String
    }

    var body: some View {
        let document = model.document
        ScrollView {
            MinutesDocumentCardView(document: document, letterheadImage: model.letterheadImage())
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Document Preview")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export as PDF")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink(value: MinutesStudioRoute.templates) {
                Text("Change Template")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .task(id: RenderKey(document: document, letterheadID: model.config.letterheadID)) {
            pdfURL = MinutesPDFRenderer.writeTemporaryPDF(document: document, letterhead: model.letterheadImage())
        }
    }
}
