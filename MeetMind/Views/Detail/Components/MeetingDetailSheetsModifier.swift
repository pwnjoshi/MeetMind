import SwiftUI

/// View modifier attaching export, ask AI, transcript edit sheets and rename alert to MeetingDetailView
public struct MeetingDetailSheetsModifier: ViewModifier {
    @Bindable public var viewModel: MeetingDetailViewModel
    @Binding public var showExportSheet: Bool
    @Binding public var showAskAISheet: Bool
    @Binding public var showRenameAlert: Bool
    @Binding public var renameText: String
    
    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showExportSheet) {
                MeetingExportSheet(
                    onExportPDF: { try? viewModel.exportPDF() },
                    onExportMarkdown: { viewModel.exportMarkdown() },
                    onExportEmailDraft: { viewModel.generateEmailDraft() },
                    onDismiss: { showExportSheet = false }
                )
            }
            .sheet(isPresented: $showAskAISheet) {
                AskAIAssistantSheet(
                    history: viewModel.aiChatHistory,
                    onAsk: { prompt in Task { _ = try? await viewModel.askAI(prompt: prompt) } },
                    onSeekToCitation: { viewModel.seekToCitation($0) },
                    onDismiss: { showAskAISheet = false }
                )
            }
            .sheet(isPresented: $viewModel.isEditingTranscript) {
                TranscriptEditSheet(
                    initialText: viewModel.editingSegmentText,
                    onSave: { viewModel.saveTranscriptEdit(newText: $0) },
                    onDismiss: { viewModel.cancelTranscriptEdit() }
                )
            }
            .alert("Rename Meeting", isPresented: $showRenameAlert) {
                TextField("Meeting Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { viewModel.renameMeeting(newTitle: renameText) }
            }
    }
}
