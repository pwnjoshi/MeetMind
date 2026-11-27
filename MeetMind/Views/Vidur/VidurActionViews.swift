import SwiftUI
import OfflineEngineKit

/// The blue bubble that shows what the user said or typed.
struct VidurPromptBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.Colors.manentAccent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("You: " + text)
    }
}

/// Confirmation card for something Vidur is about to do: schedule a meeting, add or finish an action,
/// star a meeting or start a recording. Nothing changes until the user taps the main button.
struct VidurActionCard: View {
    let intro: String
    @Binding var action: VidurPendingAction
    let state: VidurPendingState
    let result: VidurActionResult?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onOpenMeeting: (UUID) -> Void

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.Colors.manentAccent, in: Circle())
                    .accessibilityHidden(true)
                Text("Vidur").font(.subheadline.weight(.semibold))
                Spacer()
            }
            switch state {
            case .awaiting:
                Text(intro).font(.body).fixedSize(horizontal: false, vertical: true)
                details
                buttons
            case .done:
                resultView
            case .cancelled:
                Label("Cancelled. Nothing was changed.", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VidurFigma.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        switch action.kind {
        case .schedule:
            if isEditing, let draft = scheduleBinding { scheduleEditor(draft) } else { scheduleSummary }
        case .addAction(let draft, _, let meetingTitle):
            if isEditing {
                TextField("Task", text: actionTitleBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("Assigned to (leave empty for you)", text: actionAssigneeBinding)
                    .textFieldStyle(.roundedBorder)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    row("checklist", draft.title, bold: true)
                    row("person", draft.assignee ?? "You")
                    if let due = draft.due { row("calendar", "Due " + VidurActions.describe(due)) }
                    row("doc.text", "In \(meetingTitle)")
                }
            }
        case .completeAction(_, let title, let meetingTitle):
            VStack(alignment: .leading, spacing: 8) {
                row("checkmark.circle", title, bold: true)
                row("doc.text", "In \(meetingTitle)")
            }
        case .setImportant(_, let title, let important):
            VStack(alignment: .leading, spacing: 8) {
                row(important ? "star.fill" : "star.slash", title, bold: true)
            }
        case .startRecording:
            VStack(alignment: .leading, spacing: 8) {
                row("mic.fill", "Quick meeting", bold: true)
                row("lock.shield", "Recorded and processed on this iPhone")
            }
        }
    }

    private func row(_ icon: String, _ text: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(bold ? .body.weight(.semibold) : .body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scheduleSummary: some View {
        guard case .schedule(let draft) = action.kind else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                row("calendar.badge.plus", draft.title, bold: true)
                row("clock", VidurActions.describe(draft.start) + " \u{00B7} \(draft.durationMinutes) min")
                if !draft.people.isEmpty { row("person.2", draft.people.joined(separator: ", ")) }
                if let rule = draft.repeatRule { row("repeat", "Repeats " + rule.title) }
                if draft.timeAssumed {
                    Label("You didn\u{2019}t give a time, so I picked this one. Tap Edit to change it.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    private func scheduleEditor(_ draft: Binding<VidurScheduleDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: draft.title)
                .textFieldStyle(.roundedBorder)
            DatePicker("Starts", selection: draft.start)
            Stepper(value: draft.durationMinutes, in: 5...480, step: 5) {
                Text("Length: \(draft.wrappedValue.durationMinutes) min")
            }
            TextField("People (comma separated)", text: peopleBinding(draft))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
            Picker("Repeat", selection: draft.repeatRule) {
                Text("Never").tag(VidurRepeat?.none)
                ForEach([VidurRepeat.daily, .weekly, .biweekly, .monthly], id: \.self) { rule in
                    Text(String(rule.title.prefix(1)).uppercased() + String(rule.title.dropFirst())).tag(Optional(rule))
                }
            }
        }
    }

    // MARK: Buttons

    private var confirmTitle: String {
        switch action.kind {
        case .schedule: return "Schedule"
        case .addAction: return "Add action"
        case .completeAction: return "Mark done"
        case .setImportant(_, _, let important): return important ? "Star it" : "Remove star"
        case .startRecording: return "Start recording"
        }
    }

    private var canEdit: Bool {
        switch action.kind {
        case .schedule, .addAction: return true
        default: return false
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                isEditing = false
                onConfirm()
            } label: {
                Text(confirmTitle).fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.manentAccent)
            if canEdit {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    .buttonStyle(.bordered)
            }
            Button("Cancel", role: .cancel) { onCancel() }
                .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let result {
            Label {
                Text(result.message).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.succeeded ? Color.green : Color.orange)
            }
            .font(.body)
            if result.succeeded, result.recordingMeetingID == nil, let id = result.meetingID {
                Button {
                    onOpenMeeting(id)
                } label: {
                    Label("Open \(result.meetingTitle ?? "meeting")", systemImage: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.Colors.manentAccent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.manentAccent)
            }
        }
    }

    // MARK: Bindings

    private var scheduleBinding: Binding<VidurScheduleDraft>? {
        guard case .schedule = action.kind else { return nil }
        return Binding(
            get: {
                if case .schedule(let draft) = action.kind { return draft }
                return VidurScheduleDraft(title: "", start: Date())
            },
            set: { action.kind = .schedule($0) })
    }

    private func peopleBinding(_ draft: Binding<VidurScheduleDraft>) -> Binding<String> {
        Binding(
            get: { draft.wrappedValue.people.joined(separator: ", ") },
            set: { text in
                draft.wrappedValue.people = text.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            })
    }

    private var actionTitleBinding: Binding<String> {
        Binding(
            get: {
                if case .addAction(let draft, _, _) = action.kind { return draft.title }
                return ""
            },
            set: { newValue in
                if case .addAction(var draft, let id, let meetingTitle) = action.kind {
                    draft.title = newValue
                    action.kind = .addAction(draft, meetingID: id, meetingTitle: meetingTitle)
                }
            })
    }

    private var actionAssigneeBinding: Binding<String> {
        Binding(
            get: {
                if case .addAction(let draft, _, _) = action.kind { return draft.assignee ?? "" }
                return ""
            },
            set: { newValue in
                if case .addAction(var draft, let id, let meetingTitle) = action.kind {
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.assignee = trimmed.isEmpty ? nil : trimmed
                    action.kind = .addAction(draft, meetingID: id, meetingTitle: meetingTitle)
                }
            })
    }
}
