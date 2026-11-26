import SwiftUI
import SwiftData

/// "Edit Minutes": summary, agenda, attendance and decisions.
/// Text fields hold a draft until Save; Save writes through `MeetingRecordEditor` so decided-by people follow their
/// decisions and every other tab sees the change. Actions are edited in the Actions tab.
@MainActor
struct EditSavedMinutesSheet: View {
    let meeting: Meeting
    let summary: Summary

    private struct EditableDecision: Identifiable {
        let id = UUID()
        let originalIndex: Int?
        var text: String
    }

    private static let palette = ["#30B0C7", "#FF9500", "#FF2D55", "#AF52DE", "#34C759"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var overview: String
    @State private var agenda: String
    @State private var absentIDs: Set<UUID>
    @State private var decisions: [EditableDecision]
    @State private var showAddPerson = false
    @State private var saveError: String?
    private let initialOverview: String
    private let initialAbsentIDs: Set<UUID>

    init(meeting: Meeting, summary: Summary) {
        self.meeting = meeting
        self.summary = summary
        let content = MeetingMinutesContent.make(from: meeting, record: MeetingRecordData())
        let absent = Set(meeting.absentParticipantIDs ?? [])
        initialOverview = content.summary
        initialAbsentIDs = absent
        _overview = State(initialValue: content.summary)
        _agenda = State(initialValue: meeting.agendaText ?? "")
        _absentIDs = State(initialValue: absent)
        var lines: [EditableDecision] = []
        for (index, text) in summary.keyDecisions.enumerated() {
            lines.append(EditableDecision(originalIndex: index, text: text))
        }
        _decisions = State(initialValue: lines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Summary") {
                    TextField("Summary", text: $overview, axis: .vertical)
                }
                Section("Agenda") {
                    TextField("Agenda", text: $agenda, axis: .vertical)
                }
                attendeesSection
                Section {
                    ForEach($decisions) { $line in
                        decisionField($line, index: decisions.firstIndex(where: { $0.id == line.id }) ?? 0)
                    }
                    .onDelete { decisions.remove(atOffsets: $0) }
                    Button("Add Decision", systemImage: "plus") {
                        decisions.append(EditableDecision(originalIndex: nil, text: ""))
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Decisions")
                } footer: {
                    Text("Edit action items in the Actions tab. Changes there appear in these minutes.")
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
                        .toolbarConfirmButtonStyle()
                }
            }
            .sheet(isPresented: $showAddPerson) {
                MeetingAddPersonSheet(meeting: meeting)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .recordErrorAlert("Could Not Save Minutes", message: $saveError)
        }
    }

    // MARK: Attendance

    private var attendeesSection: some View {
        Section {
            ForEach(meeting.namedAttendees, id: \.id) { person in
                personRow(person)
            }
            Button {
                showAddPerson = true
            } label: {
                Label("Add Person", systemImage: "person.badge.plus")
                    .frame(minHeight: 44, alignment: .leading)
            }
        } header: {
            Text("Attendees")
        } footer: {
            Text("Tap a person to switch between present and absent.")
        }
    }

    private func personRow(_ person: Speaker) -> some View {
        let absent = absentIDs.contains(person.id)
        return Button {
            if absent { absentIDs.remove(person.id) } else { absentIDs.insert(person.id) }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: person.avatarColorHex)).frame(width: 10, height: 10)
                Text(person.name).foregroundStyle(.primary)
                Spacer()
                Text(absent ? "Absent" : "Present")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(absent ? Color.orange : Theme.Colors.manentAccent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(person.name), \(absent ? "absent" : "present")")
        .accessibilityHint(absent ? "Marks this person present" : "Marks this person absent")
    }

    // MARK: Lines

    private func decisionField(_ line: Binding<EditableDecision>, index: Int) -> some View {
        let deciderName = decider(for: line.wrappedValue.originalIndex)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Color(hex: Self.palette[index % Self.palette.count])).frame(width: 10, height: 10)
                    .padding(.top, 6)
                TextField("Decision", text: line.text, axis: .vertical)
            }
            if let deciderName {
                Text("Decided by \(deciderName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    private func decider(for originalIndex: Int?) -> String? {
        guard let originalIndex, let id = store.record(for: meeting.id).decider(at: originalIndex) else { return nil }
        return meeting.participants.first(where: { $0.id == id })?.name
    }

    // MARK: Save

    private func save() {
        let newOverview = overview.trimmingCharacters(in: .whitespacesAndNewlines)

        meeting.agendaText = agenda.trimmingCharacters(in: .whitespacesAndNewlines)
        if absentIDs != initialAbsentIDs {
            meeting.absentParticipantIDs = absentIDs.sorted { $0.uuidString < $1.uuidString }
        }
        if newOverview != initialOverview {
            summary.executiveSummary = newOverview
        }

        let edits = decisions.map { DecisionEdit(originalIndex: $0.originalIndex, text: $0.text) }
        do {
            try MeetingRecordEditor.applyDecisionEdits(edits, meeting: meeting, context: context, store: store)
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}
