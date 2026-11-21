import SwiftUI
import SwiftData

/// Connected modal sheet to edit action items presented from AppState
public struct RootEditActionItemSheet: View {
    public let actionItemId: UUID
    public let modelContext: ModelContext
    public let onDismiss: () -> Void
    
    @State private var targetItem: ActionItem?
    
    public init(actionItemId: UUID, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        self.actionItemId = actionItemId
        self.modelContext = modelContext
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ActionItemEditModal(
            existingItem: targetItem,
            onSave: { title, priority, due, assignee in
                if let item = targetItem {
                    item.title = title
                    item.priority = priority
                    item.dueDate = due
                    if let a = assignee {
                        item.assignee = Speaker(name: a)
                    }
                    try? modelContext.save()
                }
                onDismiss()
            },
            onDismiss: onDismiss
        )
        .onAppear {
            var desc = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.id == actionItemId })
            desc.fetchLimit = 1
            targetItem = try? modelContext.fetch(desc).first
        }
    }
}

/// Connected modal sheet to export minutes presented from AppState
public struct RootExportMinutesSheet: View {
    public let meetingId: UUID
    public let modelContext: ModelContext
    public let onDismiss: () -> Void
    @State private var viewModel: MeetingDetailViewModel
    
    public init(meetingId: UUID, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        self.meetingId = meetingId
        self.modelContext = modelContext
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: MeetingDetailViewModel(meetingId: meetingId, modelContext: modelContext))
    }
    
    public var body: some View {
        MeetingExportSheet(
            onExportPDF: { try viewModel.exportPDF() },
            onExportMarkdown: { viewModel.exportMarkdown() },
            onExportEmailDraft: { viewModel.generateEmailDraft() },
            onDismiss: onDismiss
        )
    }
}

/// Connected conversational AI assistant sheet presented from AppState
public struct RootAskAISheet: View {
    public let meetingId: UUID
    public let modelContext: ModelContext
    public let onDismiss: () -> Void
    @State private var viewModel: MeetingDetailViewModel
    
    public init(meetingId: UUID, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        self.meetingId = meetingId
        self.modelContext = modelContext
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: MeetingDetailViewModel(meetingId: meetingId, modelContext: modelContext))
    }
    
    public var body: some View {
        AskAIAssistantSheet(
            history: viewModel.aiChatHistory,
            onAsk: { prompt in
                viewModel.submitAIQuery(prompt) { _ in }
            },
            onSeekToCitation: { citation in
                viewModel.seekToCitation(citation)
            },
            onDismiss: { viewModel.cancelQuestion(); onDismiss() },
            meetingTitle: viewModel.headerTitle,
            isBusy: viewModel.isAnsweringQuestion,
            meeting: viewModel.meeting
        )
        .onDisappear {
                viewModel.cancelQuestion()
                viewModel.stopPlayback()
            }
    }
}
