import SwiftUI
import SwiftData

/// "People" sheet: Voices (per-speaker menus) and Who Was There (present / absent).
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

    private var voices: [MeetingVoiceRow] {
        MeetingPeopleEditor.voices(in: meeting, record: store.record(for: meeting.id))
    }

    var body: some View {
        NavigationStack {
            List {
                if !voices.isEmpty {
                    Section {
                        ForEach(voices) { row in voiceRow(row) }
                    } header: {
                        Text("Voices")
                    } footer: {
                        Text("Named people are marked present. Unnamed voices appear as Speaker 1, 2, 3 in the minutes.")
                    }
                }
                Section("Who Was There") {
                    if meeting.namedAttendees.isEmpty {
                        Text("No named people yet").foregroundStyle(.secondary)
                    }
                    ForEach(meeting.namedAttendees, id: \.id) { person in
                        let absent = MeetingPeopleEditor.isAbsent(person, in: meeting)
                        Button {
                            run { try MeetingPeopleEditor.setAbsent(!absent, person: person, meeting: meeting, context: context) }
                        } label: {
                            HStack {
                                Text(person.name).foregroundStyle(.primary)
                                Spacer()
                                if !absent { Image(systemName: "checkmark").foregroundStyle(.primary) }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(absent ? "Absent" : "Present")
                        .accessibilityHint("Toggles whether this person was there")
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
            .alert("Could Not Update People", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func voiceRow(_ row: MeetingVoiceRow) -> some View {
        HStack(spacing: 12) {
            if meeting.resolvedAudioFileURL != nil {
                Button { togglePlay(row) } label: {
                    Image(systemName: playingRowID == row.id && viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.manentAccent.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(row.label)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                Text("“\(row.sampleText)”")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            voiceMenu(row)
        }
    }

    private func voiceMenu(_ row: MeetingVoiceRow) -> some View {
        let assigned = meeting.namedAttendees.first(where: { $0.id == row.assignedPersonID })
        return Menu {
            ForEach(meeting.namedAttendees, id: \.id) { person in
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
            Button("Rename…", systemImage: "pencil") {
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
            if let assigned {
                let absent = MeetingPeopleEditor.isAbsent(assigned, in: meeting)
                Button(absent ? "Mark \(assigned.name) Present" : "Mark \(assigned.name) Absent",
                       systemImage: absent ? "person.fill.checkmark" : "person.fill.xmark") {
                    run { try MeetingPeopleEditor.setAbsent(!absent, person: assigned, meeting: meeting, context: context) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(assigned?.name ?? "Unknown").foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
            }
        }
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
