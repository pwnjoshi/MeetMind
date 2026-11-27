import SwiftUI
import SwiftData

/// Actions tab: tasks from every meeting, split into "Yours" and "Waiting on others".
/// Must not touch the SwiftData store during TabView construction. The injected
/// context is adopted in `onAppear`.
public struct ActionItemsConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?
    @Query private var queriedItems: [ActionItem]
    @State public var viewModel: ActionItemsViewModel
    @State private var syncError: String?
    @State private var selectedTaskID: UUID?
    @State private var pendingDone: ActionItem?
    @State private var showsDoneAlert = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var documentRaised = false
    @State private var showsVidur = false
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]

    public init(viewModel: ActionItemsViewModel = ActionItemsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    private var localName: String {
        settings?.userProfile?.name ?? UserProfile.defaultLocalName
    }

    public var body: some View {
        @Bindable var vm = viewModel
        let sections = viewModel.actionSections
        VStack(spacing: 0) {
            pageHeader
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            if sections.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ActionsWeekSummaryCard(summary: weekSummary)
                        ForEach(buckets) { bucket in
                            ActionsListSectionView(
                                title: bucket.title,
                                titleColor: bucket.isOverdue ? Color.red : Color.primary,
                                items: bucket.items,
                                showsOwner: true,
                                footer: nil,
                                onToggle: handleToggle,
                                onOpen: { selectedTaskID = $0.id }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { newActionButton }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        // The large title and buttons are drawn by pageHeader (Figma F1); the navigation title stays for back labels.
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.Colors.manentAccent)
        .sheet(isPresented: $showsVidur) {
            if let meeting = allMeetings.first {
                NavigationStack {
                    RootAskAISheet(meetingId: meeting.id, modelContext: modelContext) { showsVidur = false }
                }
            }
        }
        .navigationDestination(item: $selectedTaskID) { id in
            taskDetail(for: id)
        }
        .sheet(isPresented: $vm.isShowingActionItemSheet) {
            NewActionSheet(
                meetings: viewModel.availableMeetings(),
                localName: localName,
                defaultMeetingID: viewModel.sheetTargetMeetingId,
                onSave: { draft in
                    try viewModel.createAction(from: draft)
                    viewModel.selectedFilterScope = .all
                    viewModel.selectedOwnerScope = .all
                    viewModel.isShowingActionItemSheet = false
                },
                onCancel: { viewModel.cancelSheet() }
            )
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.localUserName = localName
            if viewModel.allActionItems.isEmpty && !queriedItems.isEmpty {
                viewModel.allActionItems = queriedItems
            }
        }
        .onChange(of: queriedItems) { _, newItems in
            viewModel.allActionItems = newItems
        }
        .onChange(of: localName) { _, newName in
            viewModel.localUserName = newName
        }
        .alert("Mark as done for \(pendingDone?.assignee?.name ?? "the owner")?", isPresented: $showsDoneAlert) {
            Button("Mark as Done") {
                if let item = pendingDone { viewModel.toggleCompletion(for: item) }
                pendingDone = nil
            }
            Button("Cancel", role: .cancel) { pendingDone = nil }
        } message: {
            Text("They usually mark this done themselves. Marking it here records it as done on this iPhone.")
        }
        .alert("Reminders sync failed", isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
            Button("OK") { syncError = nil }
        } message: { Text(syncError ?? "") }
    }

    private var showCompleted: Binding<Bool> {
        Binding(
            get: { viewModel.selectedFilterScope != .pending },
            set: { viewModel.selectedFilterScope = $0 ? .all : .pending }
        )
    }

    private var filterMenu: some View {
        @Bindable var vm = viewModel
        return Menu {
            Picker("Owner", selection: $vm.selectedOwnerScope) {
                Text("Assigned to Me").tag(ActionOwnerScope.assignedToMe)
                Text("Delegated").tag(ActionOwnerScope.assignedByMe)
                Text("All Actions").tag(ActionOwnerScope.all)
            }
            Divider()
            Toggle("Show Completed", isOn: showCompleted)
            Section("Sort by") {
                Picker("Sort by", selection: $vm.selectedSort) {
                    ForEach(ActionSortOrder.allCases) { order in
                        Text(order.title).tag(order)
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
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .headerCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter and sort")
    }

    private var pageHeader: some View {
        ManentPageHeader(title: "Actions") {
            filterMenu
            vidurButton
            ProfileHeaderButton(tab: .actionItems)
        }
    }

    private var vidurButton: some View {
        Button { showsVidur = true } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.manentAccent)
                .headerCircle()
        }
        .buttonStyle(.plain)
        .disabled(allMeetings.isEmpty)
        .accessibilityLabel("Ask Vidur")
    }

    private var newActionButton: some View {
        Button {
            viewModel.presentCreateSheet()
        } label: {
            CreateMenuLabel()
        }
        .modifier(GlassCircleButtonStyle())
        .padding(.trailing, 22)
        .padding(.bottom, 10)
        .accessibilityLabel("New action")
    }

    private var buckets: [ActionTimeBucket] {
        ActionTimeBucket.make(from: viewModel.visibleActionItems)
    }

    private var weekSummary: ActionWeekSummary {
        ActionWeekSummary.make(from: viewModel.allActionItems)
    }

    @ViewBuilder
    private func taskDetail(for id: UUID) -> some View {
        if let task = viewModel.allActionItems.first(where: { $0.id == id }) {
            ActionTaskDetailView(
                item: task,
                meetings: viewModel.availableMeetings(),
                localName: localName,
                onDelete: { item in
                    selectedTaskID = nil
                    viewModel.deleteActionItem(item)
                }
            )
        }
    }

    private func handleToggle(_ item: ActionItem) {
        if !item.isCompleted && viewModel.isWaitingOnOthers(item) {
            pendingDone = item
            showsDoneAlert = true
        } else {
            viewModel.toggleCompletion(for: item)
        }
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
}
