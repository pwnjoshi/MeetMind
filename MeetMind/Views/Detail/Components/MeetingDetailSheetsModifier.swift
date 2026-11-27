import SwiftUI

/// View modifier attaching export, ask AI, transcript edit sheets and rename alert to MeetingDetailView
public struct MeetingDetailSheetsModifier: ViewModifier {
    @Environment(NavigationRouter.self) private var router
    @Environment(AppState.self) private var appState
    @Bindable public var viewModel: MeetingDetailViewModel
    @Binding public var showExportSheet: Bool
    @Binding public var showAskAISheet: Bool
    @Binding public var showRenameAlert: Bool
    @Binding public var renameText: String
    var onRenameError: (Error) -> Void
    var onShareFile: ((URL) -> Void)? = nil
    
    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showExportSheet) {
                MeetingExportSheet(
                    onExportPDF: { try viewModel.exportPDF() },
                    onExportMarkdown: { viewModel.exportMarkdown() },
                    onExportEmailDraft: { viewModel.generateEmailDraft() },
                    onDismiss: { showExportSheet = false },
                    onShareFile: onShareFile
                )
            }
            .navigationDestination(isPresented: $showAskAISheet) {
                AskAIAssistantSheet(
                    history: viewModel.aiChatHistory,
                    onAsk: { prompt in viewModel.submitAIQuery(prompt) { _ in } },
                    onSeekToCitation: { viewModel.seekToCitation($0) },
                    onOpenMeeting: { meetingID in
                        showAskAISheet = false
                        appState.activeTab = .home
                        router.navigate(to: .meetingDetail(id: meetingID), in: .home)
                    },
                    onDismiss: { viewModel.cancelQuestion(); showAskAISheet = false },
                    meetingTitle: viewModel.headerTitle,
                    isBusy: viewModel.isAnsweringQuestion,
                    meeting: viewModel.meeting
                )
                .onDisappear {
                viewModel.cancelQuestion()
                viewModel.stopPlayback()
            }
            }
            .sheet(isPresented: $viewModel.isEditingTranscript) {
                TranscriptEditSheet(
                    initialText: viewModel.editingSegmentText,
                    onSave: { try viewModel.saveTranscriptEdit(newText: $0) },
                    onDismiss: { viewModel.cancelTranscriptEdit() }
                )
            }
            .alert("Rename Meeting", isPresented: $showRenameAlert) {
                TextField("Meeting Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    do { try viewModel.renameMeeting(newTitle: renameText) }
                    catch { onRenameError(error) }
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }
}
