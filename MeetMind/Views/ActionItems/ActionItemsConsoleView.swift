import SwiftUI
import SwiftData

/// Dedicated Tab 2 console aggregating all action items across all meetings
public struct ActionItemsConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Query private var queriedItems: [ActionItem]
    @State public var viewModel: ActionItemsViewModel
    @State private var syncError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var documentRaised = false
    
    public init(viewModel: ActionItemsViewModel = ActionItemsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 14) {
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
        .background(Color(hex: "#F7F7FC"))
        .navigationTitle("Actions")
        .tint(Color(hex: "#4B3FF0"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.presentCreateSheet()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New action")
                Menu {
                    Section("Group actions") {
                        ForEach(ActionItemGrouping.allCases, id: \.self) { grouping in
                            Button {
                                viewModel.selectedGrouping = grouping
                            } label: {
                                Label(groupingTitle(grouping), systemImage: viewModel.selectedGrouping == grouping ? "checkmark" : "circle")
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task {
                            do { try await viewModel.syncAllToAppleReminders() }
                            catch { syncError = error.localizedDescription }
                        }
                    } label: {
                        Label(viewModel.isSyncingReminders ? "Syncing Reminders" : "Sync Reminders", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isSyncingReminders)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
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
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(Color(uiColor: .systemGray3).opacity(index == 0 ? 1 : 0.7))
                        .frame(width: [CGFloat(30), 44, 38, 26][index], height: index == 0 ? 6 : 4)
                }
            }
            .padding(.top, 16)
            .padding(.leading, 14)
            .frame(width: 72, height: 90, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
            .offset(y: documentRaised ? -4 : 0)
            .frame(width: 140, height: 140)
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                documentRaised = false
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    documentRaised = true
                }
            }
            Text(viewModel.allActionItems.isEmpty ? "No Actions Yet" : "No Actions Here")
                .font(.title3.bold())
            Text(viewModel.allActionItems.isEmpty
                 ? "Record a meeting and its action items will appear here."
                 : "Try a different filter to see your actions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupingTitle(_ grouping: ActionItemGrouping) -> String {
        switch grouping {
        case .none: return "No grouping"
        case .priority: return "Priority"
        case .meeting: return "Meeting"
        case .assignee: return "Assignee"
        case .dueDate: return "Due date"
        case .category: return "Category"
        }
    }
}
