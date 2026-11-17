import SwiftUI
import SwiftData

/// Dedicated Tab 2 console aggregating all action items across all meetings
public struct ActionItemsConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Query private var queriedItems: [ActionItem]
    @State public var viewModel: ActionItemsViewModel
    @State private var syncError: String?
    
    public init(viewModel: ActionItemsViewModel = ActionItemsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: Spacing.sm) {
            topControlBar
            ActionItemFilterHeaderView(
                selectedScope: viewModel.selectedFilterScope,
                selectedGrouping: viewModel.selectedGrouping,
                onSelectScope: { viewModel.selectedFilterScope = $0 },
                onSelectGrouping: { viewModel.selectedGrouping = $0 }
            )
            
            if viewModel.filteredActionItems.isEmpty {
                emptyStateView
            } else {
                ActionItemGroupListView(
                    sections: viewModel.groupedActionItems,
                    onToggle: { viewModel.toggleCompletion(for: $0) },
                    onSelectMeeting: { router.navigate(to: .meetingDetail(id: $0), in: .actionItems) }
                )
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Action Items")
        .sheet(isPresented: $vm.isShowingActionItemSheet) {
            CreateActionItemSheet(
                onSave: { title, priority, due, assignee in
                    viewModel.createActionItem(title: title, priority: priority, dueDate: due, assigneeName: assignee)
                    viewModel.isShowingActionItemSheet = false
                },
                onDismiss: { viewModel.isShowingActionItemSheet = false }
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            if viewModel.allActionItems.isEmpty && !queriedItems.isEmpty {
                viewModel.allActionItems = queriedItems
            }
        }
        .onChange(of: queriedItems) { _, newItems in
            viewModel.allActionItems = newItems
        }
        .alert("Reminders sync failed", isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
            Button("OK") { syncError = nil }
        } message: { Text(syncError ?? "") }
    }
    
    private var topControlBar: some View {
        HStack {
            Button {
                Task {
                    do { try await viewModel.syncAllToAppleReminders() }
                    catch { syncError = error.localizedDescription }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(viewModel.isSyncingReminders ? "Syncing..." : "Sync Reminders")
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.aiPurple)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Theme.Colors.aiPurpleLight)
                .clipShape(Capsule())
            }
            .disabled(viewModel.isSyncingReminders)
            
            Spacer()
            
            Button {
                viewModel.presentCreateSheet()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Colors.primarySlate)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xs)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No action items match this filter").font(Typography.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
