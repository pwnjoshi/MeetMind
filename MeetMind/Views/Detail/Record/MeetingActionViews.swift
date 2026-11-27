import SwiftUI
import SwiftData
import OfflineEngineKit

/// Identifies the action being edited, or a new one when `item` is nil.
struct ActionEditTarget: Identifiable {
    let id = UUID()
    let item: ActionItem?
}

/// Context line for an action or suggestion ("For the launch checklist"), taken from the saved minutes.
enum MeetingActionContext {
    static func line(for title: String, in result: MeetingAnalysisCheckpoint?) -> String? {
        let key = MeetingEvidence.normalized(title)
        guard let action = result?.minutes?.actions.first(where: { MeetingEvidence.normalized($0.title) == key }) else {
            return nil
        }
        let topic = action.topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return topic.isEmpty ? nil : "For \(topic)"
    }
}

/// "Actions" segment: suggested actions that need review, then the accepted actions with a checkbox,
/// context line, owner and due date, and Add Action. All changes go through `MeetingRecordEditor`.
@MainActor
struct MeetingActionsList: View {
    let viewModel: MeetingDetailViewModel
    let onSyncReminders: () -> Void
    @Environment(\.modelContext) private var context
    @State private var target: ActionEditTarget?
    @State private var errorMessage: String?

    var body: some View {
        if let meeting = viewModel.meeting, let content = viewModel.minutesContent {
            page(meeting: meeting, content: content)
        }
    }

    private func page(meeting: Meeting, content: MeetingMinutesContent) -> some View {
        let analysis = meeting.offlineAnalysis
        return VStack(alignment: .leading, spacing: 20) {
            if !content.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested from the meeting")
                        .font(.headline)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(content.suggestions) { suggestion in
                        SuggestedActionCard(
                            meeting: meeting,
                            suggestion: suggestion,
                            contextLine: MeetingActionContext.line(for: suggestion.title, in: analysis)
                        )
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if !content.suggestions.isEmpty || !content.actions.isEmpty {
                    Text("Actions")
                        .font(.headline)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if content.actions.isEmpty && content.suggestions.isEmpty {
                        Text("No actions were found in this meeting.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(content.actions) { action in
                        actionRow(action, meeting: meeting, analysis: analysis)
                        Divider().padding(.leading, 56)
                    }
                    Button {
                        target = ActionEditTarget(item: nil)
                    } label: {
                        Label("Add Action", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Colors.manentAccent)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            if !content.actions.isEmpty {
                Button(action: onSyncReminders) {
                    Label("Sync to Apple Reminders", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .sheet(item: $target) { current in
            MeetingActionEditSheet(meeting: meeting, item: current.item)
        }
        .recordErrorAlert("Could Not Update Action", message: $errorMessage)
    }

    private func isDueSoon(_ action: MeetingMinutesContent.ActionLine) -> Bool {
        guard !action.isCompleted, let due = action.due else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(due) || due < calendar.startOfDay(for: Date())
    }

    private func dueText(_ action: MeetingMinutesContent.ActionLine) -> String? {
        guard let text = action.dueText else { return nil }
        if !action.isCompleted, let due = action.due, due < Calendar.current.startOfDay(for: Date()) {
            return "Overdue \(text)"
        }
        return "Due \(text)"
    }

    private func actionRow(_ action: MeetingMinutesContent.ActionLine, meeting: Meeting,
                           analysis: MeetingAnalysisCheckpoint?) -> some View {
        let item = meeting.actionItems.first(where: { $0.id == action.id })
        let contextLine = MeetingActionContext.line(for: action.title, in: analysis)
        let due = dueText(action)
        return HStack(alignment: .top, spacing: 0) {
            Button { toggle(item) } label: {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(action.isCompleted ? Theme.Colors.manentAccent : Color.secondary)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.isCompleted ? "Mark \(action.title) not done" : "Mark \(action.title) done")
            Button {
                if let item { target = ActionEditTarget(item: item) }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.body)
                            .strikethrough(action.isCompleted)
                            .foregroundStyle(action.isCompleted ? Color.secondary : Color.primary)
                            .multilineTextAlignment(.leading)
                        if let contextLine {
                            Text(contextLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(action.ownerName)
                                .foregroundStyle(.secondary)
                            if let due {
                                Text("\u{00B7}").foregroundStyle(.secondary)
                                Text(due).foregroundStyle(isDueSoon(action) ? Color.orange : Color.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this action")
        }
    }

    private func toggle(_ item: ActionItem?) {
        guard let item else { return }
        do { try MeetingRecordEditor.setCompleted(item, !item.isCompleted, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// A suggested action with Accept, Dismiss and Edit. Accepting turns it into an action item and so into the minutes;
/// dismissing removes it for good.
@MainActor
struct SuggestedActionCard: View {
    let meeting: Meeting
    let suggestion: MeetingMinutesContent.Suggestion
    let contextLine: String?
    @Environment(\.modelContext) private var modelContext
    @State private var editing: MeetingTaskSuggestion?
    @State private var errorMessage: String?

    private var ownerColor: String {
        guard let owner = suggestion.owner else { return "#8E8E93" }
        return meeting.participants.first(where: { $0.name.caseInsensitiveCompare(owner) == .orderedSame })?.avatarColorHex
            ?? "#8E8E93"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggestion.title).font(.body.weight(.semibold))
            Text(contextLine ?? suggestion.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let owner = suggestion.owner {
                    RecordAvatar(initials: RecordAvatar.initials(from: owner), colorHex: ownerColor, size: 24)
                    Text(owner).font(.subheadline)
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No owner").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let due = suggestion.deadlineText, !due.isEmpty {
                    RecordChip(title: due, tint: Color.orange)
                }
            }
            HStack(spacing: 8) {
                Button { accept() } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.Colors.manentAccent, in: Capsule())
                }
                .accessibilityLabel("Accept suggested action \(suggestion.title)")
                Button { discard() } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.Colors.manentAccent.opacity(0.1), in: Capsule())
                }
                .accessibilityLabel("Dismiss suggested action \(suggestion.title)")
                Button { editing = pending() } label: {
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Edit suggested action \(suggestion.title)")
            }
            .buttonStyle(.plain)
        }
        .recordCard()
        .sheet(item: $editing) { target in
            NavigationStack {
                SuggestedTaskEditor(meeting: meeting, suggestion: target)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", systemImage: "xmark") { editing = nil }.labelStyle(.iconOnly)
                        }
                    }
            }
        }
        .recordErrorAlert("Could Not Update Action", message: $errorMessage)
    }

    private func pending() -> MeetingTaskSuggestion? {
        meeting.pendingTaskSuggestions.first(where: { $0.id == suggestion.id })
    }

    private func accept() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.acceptSuggestion(target, meeting: meeting, context: modelContext) }
        catch { errorMessage = error.localizedDescription }
    }

    private func discard() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.discardSuggestion(target, meeting: meeting, context: modelContext) }
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
                        .toolbarConfirmButtonStyle()
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
