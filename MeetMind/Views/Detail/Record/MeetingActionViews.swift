import SwiftUI
import SwiftData

/// Identifies the action being edited, or a new one when `item` is nil.
struct ActionEditTarget: Identifiable {
    let id = UUID()
    let item: ActionItem?
}

/// "Actions" segment: accepted actions with add, edit, delete, complete and owner/due editing,
/// followed by suggested tasks that still need review. All changes go through `MeetingRecordEditor`.
@MainActor
struct MeetingActionsList: View {
    let viewModel: MeetingDetailViewModel
    let onSyncReminders: () -> Void
    @Environment(\.modelContext) private var context
    @State private var target: ActionEditTarget?
    @State private var errorMessage: String?

    var body: some View {
        if let meeting = viewModel.meeting, let content = viewModel.minutesContent {
            list(meeting: meeting, content: content)
        }
    }

    private func list(meeting: Meeting, content: MeetingMinutesContent) -> some View {
        List {
            Section {
                Button {
                    target = ActionEditTarget(item: nil)
                } label: {
                    Label("Add Action", systemImage: "plus.circle.fill")
                        .frame(minHeight: 44, alignment: .leading)
                }
                Button(action: onSyncReminders) {
                    Label("Sync to Apple Reminders", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            Section("Action Items") {
                if content.actions.isEmpty {
                    Text("No action items yet.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(content.actions) { action in
                    actionRow(action, meeting: meeting)
                }
            }
            if !content.suggestions.isEmpty {
                Section {
                    ForEach(content.suggestions) { suggestion in
                        SuggestedTaskRow(meeting: meeting, suggestion: suggestion)
                    }
                } header: {
                    Text("Suggested \u{2014} needs review")
                } footer: {
                    Text("Accepted tasks move into Action Items and the minutes. Discarded tasks are removed.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $target) { current in
            MeetingActionEditSheet(meeting: meeting, item: current.item)
        }
        .recordErrorAlert("Could Not Update Action", message: $errorMessage)
    }

    private func actionRow(_ action: MeetingMinutesContent.ActionLine, meeting: Meeting) -> some View {
        let item = meeting.actionItems.first(where: { $0.id == action.id })
        return HStack(alignment: .center, spacing: 4) {
            Button { toggle(item) } label: {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(action.isCompleted ? Theme.Colors.manentAccent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(action.isCompleted ? "Mark \(action.title) not done" : "Mark \(action.title) done")
            Button {
                if let item { target = ActionEditTarget(item: item) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline)
                        .strikethrough(action.isCompleted)
                        .foregroundStyle(action.isCompleted ? Color.secondary : Color.primary)
                    Text(MeetingActionText.detail(action))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Edit this action")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(item, from: meeting) }
        }
    }

    private func toggle(_ item: ActionItem?) {
        guard let item else { return }
        do { try MeetingRecordEditor.setCompleted(item, !item.isCompleted, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ item: ActionItem?, from meeting: Meeting) {
        guard let item else { return }
        do { try MeetingRecordEditor.deleteAction(item, from: meeting, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Add or edit one action: title, owner (from the meeting's people), due date and priority.
@MainActor
struct MeetingActionEditSheet: View {
    let meeting: Meeting
    let item: ActionItem?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var ownerID: UUID?
    @State private var dueDate: Date?
    @State private var priority: ActionPriority
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    init(meeting: Meeting, item: ActionItem?) {
        self.meeting = meeting
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _ownerID = State(initialValue: item?.assignee?.id)
        _dueDate = State(initialValue: item?.dueDate)
        _priority = State(initialValue: item?.priority ?? .medium)
    }

    private var owners: [Speaker] {
        MeetingPeopleEditor.ownerChoices(for: meeting, including: item?.assignee)
    }

    private var ownerName: String {
        owners.first(where: { $0.id == ownerID })?.name ?? "Unassigned"
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ActionFormCard {
                        TextField("Title", text: $title, axis: .vertical)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .accessibilityLabel("Action title")
                    }
                    ActionFormCard {
                        HStack {
                            Text("Due")
                            Spacer()
                            ActionDuePill(dueDate: $dueDate)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        Divider().padding(.leading, 16)
                        ownerRow
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Priority")
                            Spacer()
                            Picker("Priority", selection: $priority) {
                                ForEach(ActionPriority.allCases, id: \.self) { value in
                                    Text(value.displayName).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                    }
                    if owners.isEmpty {
                        Text("Add people in People to choose an owner.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    if item != nil {
                        Button("Delete Action", role: .destructive) { confirmDelete = true }
                            .frame(minHeight: 44)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(item == nil ? "New Action" : "Edit Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this action?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Action", role: .destructive) { remove() }
                Button("Cancel", role: .cancel) {}
            }
            .recordErrorAlert("Could Not Save Action", message: $errorMessage)
        }
        .presentationDetents([.medium, .large])
    }

    private var ownerRow: some View {
        HStack {
            Text("Owner")
            Spacer()
            Menu {
                Button("Unassigned") { ownerID = nil }
                ForEach(owners, id: \.id) { person in
                    Button {
                        ownerID = person.id
                    } label: {
                        if person.id == ownerID {
                            Label(person.name, systemImage: "checkmark")
                        } else {
                            Text(person.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(ownerName).foregroundStyle(ownerID == nil ? Color.secondary : Color.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Owner")
            .accessibilityValue(ownerName)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func save() {
        let owner = owners.first(where: { $0.id == ownerID })
        do {
            if let item {
                try MeetingRecordEditor.updateAction(item, title: title, owner: owner, dueDate: dueDate,
                                                     priority: priority, context: context)
            } else {
                try MeetingRecordEditor.addAction(title: title, owner: owner, dueDate: dueDate,
                                                  priority: priority, meeting: meeting, context: context)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        guard let item else { return }
        do {
            try MeetingRecordEditor.deleteAction(item, from: meeting, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
