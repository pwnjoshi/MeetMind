import SwiftUI

/// Modal sheet for exporting meeting minutes in PDF, Markdown, and plain text
public struct MeetingExportSheet: View {
    public let onExportPDF: () -> Data?
    public let onExportMarkdown: () -> String
    public let onExportEmailDraft: () -> EmailDraft
    public let onDismiss: () -> Void
    
    @State private var exportFormat: ExportFormat = .pdf
    @State private var exportedText: String = ""
    
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
                            _ = onExportPDF()
                        } label: { Label("Generate & Share PDF", systemImage: "doc.richtext") }
                    } else {
                        Button {
                            let text = onExportMarkdown()
                            UIPasteboard.general.string = text
                        } label: { Label("Copy Markdown to Clipboard", systemImage: "doc.on.doc") }
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
    }
}
