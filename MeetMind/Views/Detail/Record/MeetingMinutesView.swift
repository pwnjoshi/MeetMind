import SwiftUI
import SwiftData
import OfflineEngineKit

extension View {
    /// Shows `message` in an alert and clears it when dismissed.
    func recordErrorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// "Minutes" segment: the categorized record. Every section is derived from `MeetingMinutesContent`,
/// so edits made in the Actions tab, the Decisions tab, the People sheet or Edit Minutes appear here at once.
@MainActor
struct MeetingMinutesView: View {
    let meeting: Meeting
    var onOpenPeople: () -> Void = {}
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var errorMessage: String?

    var body: some View {
        let content = MeetingMinutesContent.make(from: meeting, record: store.record(for: meeting.id))
        VStack(alignment: .leading, spacing: 12) {
            summaryCard(content)
            agendaCard(content)
            attendeesCard(content)
            discussionCard(content)
            decisionsCard(content)
            actionsCard(content)
            openIssuesCard(content)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .recordErrorAlert("Could Not Update Minutes", message: $errorMessage)
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func summaryCard(_ content: MeetingMinutesContent) -> some View {
        card("Summary") {
            if content.summary.isEmpty {
                emptyText("No summary yet.")
            } else {
                Text(content.summary).font(.subheadline).textSelection(.enabled)
            }
        }
    }

    private func agendaCard(_ content: MeetingMinutesContent) -> some View {
        card("Agenda") {
            if content.agenda.isEmpty {
                emptyText("No agenda.")
            } else {
                ForEach(Array(content.agenda.enumerated()), id: \.offset) { entry in
                    Text(entry.element).font(.subheadline).textSelection(.enabled)
                }
            }
        }
    }

    private func attendeesCard(_ content: MeetingMinutesContent) -> some View {
        card("Attendees") {
            if content.present.isEmpty && content.absent.isEmpty {
                emptyText("No attendees yet.")
                Button("Add People", systemImage: "person.badge.plus", action: onOpenPeople)
                    .font(.subheadline)
                    .frame(minHeight: 44)
            } else {
                if !content.present.isEmpty {
                    Text("Present").font(.footnote).foregroundStyle(.secondary)
                    ForEach(content.present) { person in personRow(person) }
                }
                if !content.absent.isEmpty {
                    Text("Absent").font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(content.absent) { person in personRow(person) }
                }
            }
        }
    }

    private func personRow(_ person: MeetingMinutesContent.Person) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: person.colorHex)).frame(width: 10, height: 10)
            Text(person.label).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func discussionCard(_ content: MeetingMinutesContent) -> some View {
        card("Discussion") {
            if content.discussion.isEmpty {
                emptyText("No discussion points yet.")
            } else {
                ForEach(Array(content.discussion.enumerated()), id: \.offset) { entry in
                    bulletRow(entry.element)
                }
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2022}").foregroundStyle(.secondary)
            Text(text).font(.subheadline).textSelection(.enabled)
        }
    }

    private func decisionsCard(_ content: MeetingMinutesContent) -> some View {
        card("Decisions") {
            if content.decisions.isEmpty {
                emptyText("No decisions recorded.")
            } else {
                ForEach(content.decisions) { decision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.text).font(.subheadline).textSelection(.enabled)
                        if let name = decision.decidedBy {
                            Text("Decided by \(name)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func actionsCard(_ content: MeetingMinutesContent) -> some View {
        card("Action Items") {
            if content.actions.isEmpty {
                emptyText("No action items yet.")
            } else {
                ForEach(content.actions) { action in actionRow(action) }
            }
            if !content.suggestions.isEmpty {
                Text("Suggested \u{2014} needs review")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(content.suggestions) { suggestion in
                    SuggestedTaskRow(meeting: meeting, suggestion: suggestion)
                }
            }
        }
    }

    private func actionRow(_ action: MeetingMinutesContent.ActionLine) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button { toggle(action) } label: {
                Image(systemName: action.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(action.isCompleted ? Theme.Colors.manentAccent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.isCompleted ? "Mark \(action.title) not done" : "Mark \(action.title) done")
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline)
                    .strikethrough(action.isCompleted)
                    .foregroundStyle(action.isCompleted ? Color.secondary : Color.primary)
                Text(MeetingActionText.detail(action))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
    }

    private func openIssuesCard(_ content: MeetingMinutesContent) -> some View {
        card("Open Issues") {
            if content.openIssues.isEmpty {
                emptyText("No open issues.")
            } else {
                ForEach(Array(content.openIssues.enumerated()), id: \.offset) { entry in
                    bulletRow(entry.element)
                }
            }
        }
    }

    private func toggle(_ action: MeetingMinutesContent.ActionLine) {
        guard let item = meeting.actionItems.first(where: { $0.id == action.id }) else { return }
        do {
            try MeetingRecordEditor.setCompleted(item, !item.isCompleted, context: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One line of text describing an action: owner, due date and status.
enum MeetingActionText {
    static func detail(_ action: MeetingMinutesContent.ActionLine) -> String {
        var parts: [String] = [action.ownerName]
        if let due = action.dueText { parts.append("Due \(due)") }
        parts.append(action.statusText)
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// A suggested task with inline Accept, Edit and Discard.
/// Accepting turns it into an action item (and so into the minutes); discarding removes it for good.
@MainActor
struct SuggestedTaskRow: View {
    let meeting: Meeting
    let suggestion: MeetingMinutesContent.Suggestion
    @Environment(\.modelContext) private var context
    @State private var editing: MeetingTaskSuggestion?
    @State private var errorMessage: String?

    private var detail: String {
        var parts: [String] = []
        if let owner = suggestion.owner { parts.append("Owner: \(owner)") }
        if let deadline = suggestion.deadlineText, !deadline.isEmpty { parts.append("Due: \(deadline)") }
        parts.append(suggestion.category)
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(suggestion.title).font(.subheadline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Accept") { accept() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Accept suggested task \(suggestion.title)")
                Button("Edit") { editing = pending() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Edit suggested task \(suggestion.title)")
                Button("Discard", role: .destructive) { discard() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Discard suggested task \(suggestion.title)")
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 6)
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
        .recordErrorAlert("Could Not Update Task", message: $errorMessage)
    }

    private func pending() -> MeetingTaskSuggestion? {
        meeting.pendingTaskSuggestions.first(where: { $0.id == suggestion.id })
    }

    private func accept() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.acceptSuggestion(target, meeting: meeting, context: context) }
        catch { errorMessage = error.localizedDescription }
    }

    private func discard() {
        guard let target = pending() else { return }
        do { try MeetingRecordEditor.discardSuggestion(target, meeting: meeting, context: context) }
        catch { errorMessage = error.localizedDescription }
    }
}
