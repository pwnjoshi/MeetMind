import SwiftUI

/// Modal sheet for exporting meeting minutes in PDF, Markdown, and plain text
public struct MeetingExportSheet: View {
    public let onExportPDF: () -> Data?
    public let onExportMarkdown: () -> String
    public let onExportEmailDraft: () -> EmailDraft
    public let onDismiss: () -> Void
    
    @State private var exportFormat: ExportFormat = .pdf
    @State private var exportedText: String = ""
    @State private var exportedURL: URL?
    @State private var exportError: String?
    
    public init(
        onExportPDF: @escaping () -> Data?,
        onExportMarkdown: @escaping () -> String,
        onExportEmailDraft: @escaping () -> EmailDraft,
        onDismiss: @escaping () -> Void
    ) {
        self.onExportPDF = onExportPDF
        self.onExportMarkdown = onExportMarkdown
        self.onExportEmailDraft = onExportEmailDraft
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("Export Format") {
                    Picker("Format", selection: $exportFormat) {
                        Text("PDF Minutes").tag(ExportFormat.pdf)
                        Text("Markdown Document").tag(ExportFormat.markdownText)
                        Text("Plain Text").tag(ExportFormat.plainText)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Actions") {
                    if exportFormat == .pdf {
                        Button {
                            do {
                                guard let data = onExportPDF(), !data.isEmpty else {
                                    exportError = "Could not generate the PDF. Please try again."
                                    return
                                }
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeetMind-\(UUID().uuidString).pdf")
                                try data.write(to: url, options: .atomic)
                                exportedURL = url
                            } catch { exportError = error.localizedDescription }
                        } label: { Label("Generate & Share PDF", systemImage: "doc.richtext") }
                        if let exportedURL {
                            ShareLink(item: exportedURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                        }
                    } else {
                        Button {
                            let text = exportFormat == .plainText ? onExportEmailDraft().body : onExportMarkdown()
                            UIPasteboard.general.string = text
                        } label: { Label(exportFormat == .plainText ? "Copy Plain Text" : "Copy Markdown", systemImage: "doc.on.doc") }
                    }
                    
                    Button {
                        let draft = onExportEmailDraft()
                        UIPasteboard.general.string = "\(draft.subject)\n\n\(draft.body)"
                    } label: { Label("Copy Email Draft", systemImage: "envelope") }
                }
            }
            .navigationTitle("Export Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDismiss) }
            }
        }
        .presentationDetents([.medium])
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }
}
