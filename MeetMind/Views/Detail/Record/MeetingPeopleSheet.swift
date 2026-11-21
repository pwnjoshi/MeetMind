import SwiftUI
import SwiftData

/// "People" sheet. Attendees: everyone who was in the meeting, spoken or not, present or absent.
/// Detected Voices: unnamed or assigned voices from the transcript.
@MainActor
struct MeetingPeopleSheet: View {
    let meeting: Meeting
    let viewModel: MeetingDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var renameRow: MeetingVoiceRow?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var playingRowID: String?
    @State private var showAddPerson = false
    @State private var editingPerson: Speaker?
    @State private var removalCandidate: Speaker?

    private var voices: [MeetingVoiceRow] {
        MeetingPeopleEditor.voices(in: meeting, record: store.record(for: meeting.id))
    }

    var body: some View {
        NavigationStack {
            List {
                attendeesSection
                if !voices.isEmpty {
                    Section {
                        ForEach(voices) { row in voiceRow(row) }
                    } header: {
                        Text("Detected Voices")
                    } footer: {
                        Text("Assign a voice to a person to name them in the transcript. Unnamed voices appear as Speaker 1, 2, 3 in the minutes.")
                    }
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        viewModel.stopPlayback()
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                }
            }
            .sheet(isPresented: $showAddPerson) {
                MeetingAddPersonSheet(meeting: meeting)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingPerson) { person in
                MeetingPersonEditSheet(meeting: meeting, person: person)
            }
            .confirmationDialog(
                "Remove from this meeting?",
                isPresented: Binding(get: { removalCandidate != nil }, set: { if !$0 { removalCandidate = nil } }),
                titleVisibility: .visible
            ) {
                if let person = removalCandidate {
                    Button("Remove \(person.name)", role: .destructive) {
                        run { try MeetingPeopleEditor.removeAttendee(person, from: meeting, context: context) }
                        removalCandidate = nil
                    }
                }
                Button("Cancel", role: .cancel) { removalCandidate = nil }
            } message: {
                Text("They stay in your people list and keep any actions they own.")
            }
            .alert("Name This Voice", isPresented: Binding(
                get: { renameRow != nil }, set: { if !$0 { renameRow = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameRow = nil }
                Button("Save") {
                    if let row = renameRow {
                        run { try MeetingPeopleEditor.rename(row, to: renameText, meeting: meeting, context: context, store: store) }
                    }
                    renameRow = nil
                }
            }
            .recordErrorAlert("Could Not Update People", message: $errorMessage)
        }
    }

    // MARK: Attendees

    private var attendeesSection: some View {
        Section {
            Button {
                showAddPerson = true
            } label: {
                Label("Add Person", systemImage: "person.badge.plus")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityHint("Add someone who was in the meeting, even if they did not speak")
            if meeting.namedAttendees.isEmpty {
                Text("No one added yet. Add people who attended, even if they did not speak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(meeting.namedAttendees, id: \.id) { person in
                attendeeRow(person)
            }
        } header: {
            Text("Attendees")
        } footer: {
            Text("Tap a person to switch between present and absent. Attendees can own actions and decisions.")
        }
    }

    private func attendeeRow(_ person: Speaker) -> some View {
        let absent = MeetingPeopleEditor.isAbsent(person, in: meeting)
        let canRemove = MeetingPeopleEditor.canRemove(person, from: meeting)
        return HStack(spacing: 4) {
            Button {
                run { try MeetingPeopleEditor.setAbsent(!absent, person: person, meeting: meeting, context: context) }
            } label: {
                HStack(spacing: 12) {
                    Text(person.initials)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: person.avatarColorHex), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.subheadline).foregroundStyle(.primary)
                        if let role = person.role, !role.isEmpty {
                            Text(role).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(absent ? "Absent" : "Present")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(absent ? Color.orange : Theme.Colors.manentAccent)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(person.name), \(absent ? "absent" : "present")")
            .accessibilityHint(absent ? "Marks this person present" : "Marks this person absent")
            Menu {
                Button("Edit Details", systemImage: "pencil") { editingPerson = person }
                Button(absent ? "Mark Present" : "Mark Absent",
                       systemImage: absent ? "person.fill.checkmark" : "person.fill.xmark") {
                    run { try MeetingPeopleEditor.setAbsent(!absent, person: person, meeting: meeting, context: context) }
                }
                if canRemove {
                    Divider()
                    Button("Remove from Meeting", systemImage: "person.badge.minus", role: .destructive) {
                        removalCandidate = person
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(person.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canRemove {
                Button("Remove", systemImage: "person.badge.minus", role: .destructive) { removalCandidate = person }
            }
        }
    }

    // MARK: Detected voices

    private func voiceRow(_ row: MeetingVoiceRow) -> some View {
        HStack(spacing: 12) {
            if meeting.resolvedAudioFileURL != nil {
                Button { togglePlay(row) } label: {
                    Image(systemName: playingRowID == row.id && viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 44, height: 44)
                        .background(Theme.Colors.manentAccent.opacity(0.1), in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play \(row.label)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.subheadline)
                Text("\u{201C}\(row.sampleText)\u{201D}")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            voiceMenu(row)
        }
        .frame(minHeight: 44)
    }

    private func voiceMenu(_ row: MeetingVoiceRow) -> some View {
        let people = meeting.namedAttendees
        let assigned = people.first(where: { $0.id == row.assignedPersonID })
        let assignedName = assigned?.name ?? "Unknown"
        return Menu {
            ForEach(people, id: \.id) { person in
                Button {
                    run { try MeetingPeopleEditor.assign(row, to: person, meeting: meeting, context: context, store: store) }
                } label: {
                    if person.id == row.assignedPersonID {
                        Label(person.name, systemImage: "checkmark")
                    } else {
                        Text(person.name)
                    }
                }
            }
            Button("Keep as Unknown") {
                run { try MeetingPeopleEditor.keepUnknown(row, meeting: meeting, context: context, store: store) }
            }
            Divider()
            Button("Name as New Person\u{2026}", systemImage: "person.badge.plus") {
                renameText = assigned?.name ?? ""
                renameRow = row
            }
            let others = voices.filter { $0.id != row.id }
            if !others.isEmpty {
                Menu("Merge Into", systemImage: "arrow.triangle.merge") {
                    ForEach(others) { other in
                        Button(displayName(other)) {
                            run { try MeetingPeopleEditor.merge(row, into: other, meeting: meeting, context: context, store: store) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(assignedName).font(.subheadline).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Assign \(row.label)")
        .accessibilityValue(assignedName)
    }

    private func displayName(_ row: MeetingVoiceRow) -> String {
        for person in meeting.namedAttendees where person.id == row.assignedPersonID { return person.name }
        return row.label
    }

    private func togglePlay(_ row: MeetingVoiceRow) {
        if playingRowID == row.id && viewModel.isPlaying {
            viewModel.stopPlayback()
            playingRowID = nil
        } else {
            viewModel.seek(to: row.startTime)
            if !viewModel.isPlaying { viewModel.togglePlayPause() }
            playingRowID = row.id
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
