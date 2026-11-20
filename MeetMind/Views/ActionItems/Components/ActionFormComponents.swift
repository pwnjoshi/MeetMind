import SwiftUI

/// Rounded white card used by the action forms.
struct ActionFormCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Grey capsule showing the due date. Tapping opens a graphical calendar popover.
struct ActionDuePill: View {
    @Binding var dueDate: Date?
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            Text(dueDate.map { ActionListLogic.shortDate($0) } ?? "None")
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Due date")
        .accessibilityValue(dueDate.map { ActionListLogic.shortDate($0) } ?? "None")
        .popover(isPresented: $showsPopover) {
            ActionDuePopover(dueDate: $dueDate) { showsPopover = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ActionDuePopover: View {
    @Binding var dueDate: Date?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            DatePicker(
                "Due",
                selection: Binding(get: { dueDate ?? Date() }, set: { dueDate = $0 }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            HStack {
                Button("No Due Date", role: .destructive) {
                    dueDate = nil
                    onClose()
                }
                .disabled(dueDate == nil)
                Spacer()
                Button("Done", action: onClose)
                    .fontWeight(.semibold)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

/// "Assigned To" menu: local user, meeting participants, added people, and "New Person".
struct ActionOwnerMenu: View {
    @Binding var ownerName: String?
    let options: [String]
    let localName: String
    let onNewPerson: () -> Void

    private func display(_ name: String) -> String {
        name.caseInsensitiveCompare(localName) == .orderedSame ? "Me" : name
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { name in
                Button {
                    ownerName = name
                } label: {
                    if ownerName == name {
                        Label(display(name), systemImage: "checkmark")
                    } else {
                        Text(display(name))
                    }
                }
            }
            Divider()
            Button {
                ownerName = nil
            } label: {
                if ownerName == nil {
                    Label("Unassigned", systemImage: "checkmark")
                } else {
                    Text("Unassigned")
                }
            }
            Button(action: onNewPerson) {
                Label("New Person", systemImage: "person.badge.plus")
            }
        } label: {
            HStack(spacing: 6) {
                Text(ownerName.map { display($0) } ?? "Unassigned")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Assigned to")
    }
}

/// Meeting picker menu with a "No Meeting" choice.
struct ActionMeetingMenu: View {
    @Binding var meetingID: UUID?
    let meetings: [Meeting]

    var body: some View {
        Menu {
            Button {
                meetingID = nil
            } label: {
                if meetingID == nil {
                    Label("No Meeting", systemImage: "checkmark")
                } else {
                    Text("No Meeting")
                }
            }
            ForEach(meetings, id: \.id) { meeting in
                Button {
                    meetingID = meeting.id
                } label: {
                    if meetingID == meeting.id {
                        Label(meeting.title, systemImage: "checkmark")
                    } else {
                        Text(meeting.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(meetings.first(where: { $0.id == meetingID })?.title ?? "No Meeting")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Meeting")
    }
}

/// Title and notes card plus the Due, Assigned To, and Meeting rows.
struct ActionFormCards: View {
    @Binding var draft: ActionDraft
    let meetings: [Meeting]
    let localName: String
    /// New Action lists Due first; the task detail lists Assigned To first.
    let dueFirst: Bool

    @State private var showsNewPerson = false
    @State private var newPersonName = ""

    private var selectedMeeting: Meeting? {
        meetings.first { $0.id == draft.meetingID }
    }

    var body: some View {
        VStack(spacing: 16) {
            ActionFormCard {
                TextField("Title", text: $draft.title)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                Divider().padding(.leading, 16)
                TextField("Notes", text: $draft.note, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            ActionFormCard {
                if dueFirst {
                    dueRow
                    Divider().padding(.leading, 16)
                    ownerRow
                } else {
                    ownerRow
                    Divider().padding(.leading, 16)
                    dueRow
                }
                Divider().padding(.leading, 16)
                meetingRow
            }
        }
        .alert("New Person", isPresented: $showsNewPerson) {
            TextField("Name", text: $newPersonName)
            Button("Cancel", role: .cancel) { newPersonName = "" }
            Button("Add") { addPerson() }
        } message: {
            Text("They are added to this action only.")
        }
    }

    private var dueRow: some View {
        HStack {
            Text("Due")
            Spacer()
            ActionDuePill(dueDate: $draft.dueDate)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var ownerRow: some View {
        HStack {
            Text("Assigned To")
            Spacer()
            ActionOwnerMenu(
                ownerName: $draft.ownerName,
                options: ActionListLogic.ownerOptions(
                    localName: localName,
                    meeting: selectedMeeting,
                    extras: draft.extraOwners,
                    current: draft.ownerName
                ),
                localName: localName,
                onNewPerson: { showsNewPerson = true }
            )
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private var meetingRow: some View {
        HStack {
            Text("Meeting")
            Spacer()
            ActionMeetingMenu(meetingID: $draft.meetingID, meetings: meetings)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPersonName = ""
        guard !name.isEmpty else { return }
        if !draft.extraOwners.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            draft.extraOwners.append(name)
        }
        draft.ownerName = name
    }
}
