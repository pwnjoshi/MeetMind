import SwiftUI
import SwiftData

private struct TaskDetailSheet: View {
    let task: ActionItem
    let openMeeting: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var assignee: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var errorMessage: String?

    init(task: ActionItem, openMeeting: @escaping (UUID) -> Void) {
        self.task = task
        self.openMeeting = openMeeting
        _assignee = State(initialValue: task.assignee?.name ?? "")
        _dueDate = State(initialValue: task.dueDate ?? .now)
        _hasDueDate = State(initialValue: task.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(task.title).font(.headline) }
                    .listRowBackground(Color.clear)
                Section {
                    LabeledContent("Assigned To") {
                        TextField("Unassigned", text: $assignee)
                            .multilineTextAlignment(.trailing)
                    }
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        Button("Remove Due Date") { hasDueDate = false }
                    } else {
                        Button("Add Due Date") { hasDueDate = true }
                    }
                }
                if let meeting = task.meeting {
                    Section("Meeting") {
                        Button { openMeeting(meeting.id) } label: {
                            HStack {
                                Text(meeting.title)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }.labelStyle(.iconOnly)
                }
            }
            .alert("Could Not Save Action", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let name = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = (task.assignee, task.assignedByLocalUser, task.dueDate)
        let newSpeaker: Speaker? = name.isEmpty || name == previous.0?.name ? nil : Speaker(name: name)
        if name != (previous.0?.name ?? "") {
            task.assignee = newSpeaker
            task.assignedByLocalUser = newSpeaker == nil ? nil : true
        }
        task.dueDate = hasDueDate ? dueDate : nil
        do {
            try context.save()
            dismiss()
        } catch {
            task.assignee = previous.0
            task.assignedByLocalUser = previous.1
            task.dueDate = previous.2
            if let newSpeaker, newSpeaker.modelContext != nil { context.delete(newSpeaker) }
            errorMessage = error.localizedDescription
        }
    }
}

/// Dedicated Tab 2 console aggregating all action items across all meetings
public struct ActionItemsConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings: SettingsViewModel?
    @Query private var queriedItems: [ActionItem]
    @State public var viewModel: ActionItemsViewModel
    @State private var syncError: String?
    @State private var selectedTask: ActionItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var documentRaised = false
    
    public init(viewModel: ActionItemsViewModel = ActionItemsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        @Bindable var vm = viewModel
        Group {
            if visibleActions.isEmpty {
                emptyStateView
            } else {
                FigmaActionsList(
                    yours: assignedToMe,
                    waitingOnOthers: waitingOnOthers,
                    onToggle: { viewModel.toggleCompletion(for: $0) },
                    onSelectMeeting: { router.navigate(to: .meetingDetail(id: $0), in: .actionItems) },
                    onOpenTask: { selectedTask = $0 }
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
                    Picker("Status", selection: $vm.selectedFilterScope) {
                        Text("All statuses").tag(ActionItemFilterScope.all)
                        Text("Open").tag(ActionItemFilterScope.pending)
                        Text("Done").tag(ActionItemFilterScope.completed)
                    }
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
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task) { id in
                selectedTask = nil
                router.navigate(to: .meetingDetail(id: id), in: .actionItems)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $vm.isShowingActionItemSheet) {
            CreateActionItemSheet(
                onSave: { title, priority, due, assignee in
                    viewModel.createActionItem(title: title, priority: priority, dueDate: due, assigneeName: assignee)
                    viewModel.selectedFilterScope = .all
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

    private var visibleActions: [ActionItem] {
        viewModel.allActionItems.filter { item in
            switch viewModel.selectedFilterScope {
            case .all: return true
            case .pending: return !item.isCompleted
            case .completed: return item.isCompleted
            case .urgent: return !item.isCompleted && item.priority == .urgent
            case .dueSoon:
                guard !item.isCompleted, let dueDate = item.dueDate else { return false }
                return dueDate <= Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? dueDate
            }
        }
    }

    private var assignedToMe: [ActionItem] {
        let localName = settings?.userProfile?.name ?? UserProfile.defaultLocalName
        return visibleActions.filter { $0.assignee?.name.localizedCaseInsensitiveCompare(localName) == .orderedSame }
    }

    private var waitingOnOthers: [ActionItem] {
        let localName = settings?.userProfile?.name ?? UserProfile.defaultLocalName
        return visibleActions.filter { $0.assignee?.name.localizedCaseInsensitiveCompare(localName) != .orderedSame }
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

private struct FigmaActionsList: View {
    let yours: [ActionItem]
    let waitingOnOthers: [ActionItem]
    let onToggle: (ActionItem) -> Void
    let onSelectMeeting: (UUID) -> Void
    let onOpenTask: (ActionItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !yours.isEmpty { section("Yours", items: yours) }
                if !waitingOnOthers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        section("Waiting on others", items: waitingOnOthers)
                        Text("They tick these off from their task link.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
    }

    private func section(_ title: String, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    FigmaActionRow(item: item, onToggle: { onToggle(item) }, onOpen: { onOpenTask(item) }, onSelectMeeting: onSelectMeeting)
                    if index < items.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct FigmaActionRow: View {
    let item: ActionItem
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onSelectMeeting: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(item.isCompleted ? Theme.Colors.manentAccent : .secondary)
                    .frame(width: 28, height: 44)
            }.buttonStyle(.plain)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).foregroundStyle(.primary).strikethrough(item.isCompleted)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }.buttonStyle(.plain)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).frame(minHeight: 66)
    }

    private var subtitle: String {
        let due = item.dueDate.map { $0 < .now ? "Overdue" : $0.formatted(date: .abbreviated, time: .omitted) }
        let owner = item.assignee?.name
        let meeting = item.meeting?.title
        return [due, owner, meeting].compactMap { $0 }.joined(separator: " · ")
    }
}
