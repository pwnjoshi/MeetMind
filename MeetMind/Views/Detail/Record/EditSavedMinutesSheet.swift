import SwiftUI
import SwiftData

/// "Edit Minutes": agenda, present / absent people, discussion, decisions and action items.
struct EditSavedMinutesSheet: View {
    let meeting: Meeting
    let summary: Summary

    private struct EditableLine: Identifiable {
        let id = UUID()
        var text: String
    }

    private struct EditablePerson: Identifiable {
        let id: UUID
        var name: String
        var colorHex: String
        var isNew: Bool
    }

    private static let palette = ["#30B0C7", "#FF9500", "#FF2D55", "#AF52DE", "#34C759"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var agenda: String
    @State private var people: [EditablePerson]
    @State private var absentIDs: Set<UUID>
    @State private var discussion: [EditableLine]
    @State private var decisions: [EditableLine]
    @State private var actionTitles: [UUID: String]
    @State private var showAddPerson = false
    @State private var newPersonName = ""
    @State private var saveError: String?

    init(meeting: Meeting, summary: Summary) {
        self.meeting = meeting
        self.summary = summary
        _agenda = State(initialValue: meeting.agendaText ?? "")
        _people = State(initialValue: meeting.namedAttendees.map {
            EditablePerson(id: $0.id, name: $0.name, colorHex: $0.avatarColorHex, isNew: false)
        })
        _absentIDs = State(initialValue: Set(meeting.absentParticipantIDs ?? []))
        _discussion = State(initialValue: summary.discussionLines.map { EditableLine(text: $0) })
        _decisions = State(initialValue: summary.keyDecisions.map { EditableLine(text: $0) })
        var titles: [UUID: String] = [:]
        for item in meeting.actionItems { titles[item.id] = item.title }
        _actionTitles = State(initialValue: titles)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agenda") {
                    TextField("Agenda", text: $agenda, axis: .vertical)
                }
                Section("Present") {
                    ForEach(people.filter { !absentIDs.contains($0.id) }) { person in
                        personRow(person, absent: false)
                    }
                    Button {
                        newPersonName = ""
                        showAddPerson = true
                    } label: {
                        Label {
                            Text("Add Participant").foregroundStyle(Theme.Colors.manentAccent)
                        } icon: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                if people.contains(where: { absentIDs.contains($0.id) }) {
                    Section("Absent") {
                        ForEach(people.filter { absentIDs.contains($0.id) }) { person in
                            personRow(person, absent: true)
                        }
                    }
                }
                Section("Discussion") {
                    ForEach($discussion) { $line in
                        lineField($line, index: discussion.firstIndex(where: { $0.id == line.id }) ?? 0)
                    }
                    .onDelete { discussion.remove(atOffsets: $0) }
                    Button("Add Discussion Point", systemImage: "plus") { discussion.append(EditableLine(text: "")) }
                }
                Section("Decision") {
                    ForEach($decisions) { $line in
                        lineField($line, index: decisions.firstIndex(where: { $0.id == line.id }) ?? 0)
                    }
                    .onDelete { decisions.remove(atOffsets: $0) }
                    Button("Add Decision", systemImage: "plus") { decisions.append(EditableLine(text: "")) }
                }
                if !meeting.actionItems.isEmpty {
                    Section("Action items") {
                        ForEach(meeting.actionItems) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Action item", text: titleBinding(for: item), axis: .vertical)
                                Text(actionDetails(item)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Minutes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Minutes", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                }
            }
            .alert("Add Participant", isPresented: $showAddPerson) {
                TextField("Name", text: $newPersonName)
                Button("Cancel", role: .cancel) {}
                Button("Add") { addPerson() }
            }
            .alert("Could Not Save Minutes", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    private func personRow(_ person: EditablePerson, absent: Bool) -> some View {
        Button {
            if absent { absentIDs.remove(person.id) } else { absentIDs.insert(person.id) }
        } label: {
            Label {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: person.colorHex)).frame(width: 10, height: 10)
                    Text(person.name).foregroundStyle(.primary)
                }
            } icon: {
                Image(systemName: absent ? "plus.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(absent ? Color.green : Color.red)
            }
        }
        .accessibilityLabel("Mark \(person.name) \(absent ? "present" : "absent")")
    }

    private func lineField(_ line: Binding<EditableLine>, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: Self.palette[index % Self.palette.count])).frame(width: 10, height: 10)
                .padding(.top, 6)
            TextField("Text", text: line.text, axis: .vertical)
        }
    }

    private func titleBinding(for item: ActionItem) -> Binding<String> {
        Binding(
            get: { actionTitles[item.id] ?? item.title },
            set: { actionTitles[item.id] = $0 }
        )
    }

    private func actionDetails(_ action: ActionItem) -> String {
        guard let date = action.dueDate else { return action.assigneeName }
        return "\(action.assigneeName) · Due \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !people.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        people.append(EditablePerson(id: UUID(), name: name,
                                     colorHex: Self.palette[people.count % Self.palette.count], isNew: true))
    }

    private func clean(_ lines: [EditableLine]) -> [String] {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func save() {
        let oldDecisions = summary.keyDecisions
        meeting.agendaText = agenda.trimmingCharacters(in: .whitespacesAndNewlines)
        for person in people where person.isNew {
            let speaker = Speaker(id: person.id, name: person.name, avatarColorHex: person.colorHex)
            context.insert(speaker)
            meeting.addParticipant(speaker)
        }
        meeting.absentParticipantIDs = absentIDs.sorted { $0.uuidString < $1.uuidString }
        let discussionLines = clean(discussion)
        if discussionLines != summary.discussionLines {
            summary.executiveSummary = discussionLines.joined(separator: "\n")
            summary.keyPoints = discussionLines
        }
        let newDecisions = clean(decisions)
        summary.keyDecisions = newDecisions
        for item in meeting.actionItems {
            let title = (actionTitles[item.id] ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title != item.title { item.title = title }
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
            return
        }
        do {
            try MeetingRecordStore.shared.update(meeting.id) {
                $0.remapDeciders(oldDecisions: oldDecisions, newDecisions: newDecisions)
            }
        } catch {
            saveError = error.localizedDescription
            return
        }
        dismiss()
    }
}
