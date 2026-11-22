import SwiftUI
import SwiftData

/// Task detail pushed from the Actions list.
struct ActionTaskDetailView: View {
    let item: ActionItem
    let meetings: [Meeting]
    let localName: String
    let onDelete: (ActionItem) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationRouter.self) private var router

    @State private var draft: ActionDraft
    @State private var response: TaskResponse?
    @State private var errorMessage: String?
    @State private var showsDoneAlert = false
    @State private var showsDeleteConfirm = false
    @State private var showsResponse = false
    @State private var showsRepeat = false
    @State private var isRemoved = false
    @State private var isCompleted: Bool

    init(item: ActionItem, meetings: [Meeting], localName: String, onDelete: @escaping (ActionItem) -> Void) {
        self.item = item
        self.meetings = meetings
        self.localName = localName
        self.onDelete = onDelete
        _draft = State(initialValue: ActionDraft(item: item))
        _isCompleted = State(initialValue: item.isCompleted)
    }

    private var isWaitingOnOthers: Bool {
        ActionListLogic.isWaitingOnOthers(item, localName: localName)
    }

    private var ownerName: String {
        item.assignee?.name ?? ""
    }

    var body: some View {
        Group {
            if isRemoved {
                Color.clear
            } else {
                content
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ActionFormCards(
                    draft: $draft,
                    meetings: meetings,
                    localName: localName,
                    dueFirst: false,
                    showsTitle: false,
                    showsNotes: false
                )
                if let meeting = item.meeting {
                    meetingCard(meeting)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").font(.title3.weight(.semibold)).padding(.horizontal, 2)
                    ActionNotesCard(note: $draft.note, placeholder: "Add a note")
                }
                .padding(.top, 8)
                completionCard
                if isWaitingOnOthers {
                    assignmentCard
                }
                Button(role: .destructive) {
                    showsDeleteConfirm = true
                } label: {
                    Text("Delete Action")
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Action")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!draft.isValid || draft == ActionDraft(item: item))
            }
        }
        .onAppear {
            response = TaskResponseStore.shared.response(for: item.id)
        }
        .navigationDestination(isPresented: $showsResponse) {
            TaskAssignmentResponseView(item: item, ownerName: ownerName) { recorded in
                response = recorded
            }
        }
        .sheet(isPresented: $showsRepeat) {
            if let meeting = item.meeting {
                RepeatMeetingSheet(meeting: meeting)
            }
        }
        .alert("Mark as done for \(ownerName)?", isPresented: $showsDoneAlert) {
            Button("Mark as Done") { setCompleted(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They usually mark this done themselves. Marking it here records it as done on this iPhone.")
        }
        .confirmationDialog("Delete this action?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Action", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could Not Update Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Cards

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pill = statusPill {
                Text(pill.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(pill.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(pill.color.opacity(0.14), in: Capsule())
            }
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(.title.bold())
                .accessibilityLabel("Action title")
        }
    }

    private var statusPill: (text: String, color: Color)? {
        if isCompleted { return ("Done", Color.green) }
        guard let due = ActionListLogic.dueInfo(for: item) else { return nil }
        if due.isOverdue {
            let day = item.dueDate?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
            return ("Overdue \u{00B7} \(day)", Color.red)
        }
        return (due.text, Theme.Colors.manentAccent)
    }

    private func meetingCard(_ meeting: Meeting) -> some View {
        ActionFormCard {
            VStack(alignment: .leading, spacing: 10) {
                if let evidence = item.sourceEvidence, !evidence.isEmpty {
                    Text("Said in the Meeting")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\u{201C}\(evidence)\u{201D}")
                        .font(.body)
                        .textSelection(.enabled)
                }
                Button {
                    router.navigate(to: .meetingDetail(id: meeting.id), in: .actionItems)
                } label: {
                    HStack {
                        Label("Open \(meeting.title)", systemImage: "calendar")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
                Button {
                    showsRepeat = true
                } label: {
                    HStack {
                        Label("Repeat Meeting", systemImage: "repeat")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private var completionCard: some View {
        Button {
            if isCompleted {
                setCompleted(false)
            } else if isWaitingOnOthers {
                showsDoneAlert = true
            } else {
                setCompleted(true)
            }
        } label: {
            Text(isCompleted ? "Done. Tap to reopen" : "Mark as Done")
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.Colors.manentAccent)
    }
    private var assignmentCard: some View {
        ActionFormCard {
            VStack(alignment: .leading, spacing: 0) {
                if let response {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Owner response")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(response.summary)
                        Text("Recorded by you on \(response.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    Divider().padding(.leading, 16)
                }
                Button {
                    showsResponse = true
                } label: {
                    HStack {
                        Text(response == nil ? "Record Owner's Response" : "Update Owner's Response")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
                ShareLink(item: assignmentShareText) {
                    HStack {
                        Label("Share Assignment", systemImage: "square.and.arrow.up")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var assignmentShareText: String {
        var lines = ["Task for \(ownerName): \(item.title)"]
        if let due = item.dueDate {
            lines.append("Due \(ActionListLogic.shortDate(due))")
        }
        if let meeting = item.meeting {
            lines.append("Meeting: \(meeting.title)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Actions

    private func save() {
        do {
            try ActionItemWriter.apply(draft, to: item, meetings: meetings, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setCompleted(_ done: Bool) {
        guard item.isCompleted != done else {
            isCompleted = done
            return
        }
        item.toggleCompleted()
        do {
            try context.save()
            isCompleted = item.isCompleted
        } catch {
            item.toggleCompleted()
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        // The owner of this view pops it and deletes the item in `onDelete`.
        isRemoved = true
        onDelete(item)
    }
}
