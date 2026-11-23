import SwiftUI
import SwiftData
import OfflineEngineKit

/// A name the minutes engine suggested for an attendee, with the reason it gave.
struct NameSpeakerSuggestion: Identifiable, Equatable, Sendable {
    let name: String
    let reason: String
    var id: String { name.lowercased() }

    /// Reads minutes -> suggestedAttendees from the stored offline analysis JSON.
    static func parse(_ data: Data?) -> [NameSpeakerSuggestion] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let minutes = root["minutes"] as? [String: Any],
              let items = minutes["suggestedAttendees"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var result: [NameSpeakerSuggestion] = []
        for item in items {
            let name = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            let reason = (item["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(NameSpeakerSuggestion(name: name, reason: reason))
        }
        return result
    }
}

/// B5 Name speakers. One card per detected voice with short clips to play, quick-assign
/// chips for the meeting's people and names the engine suggested, and a menu for the rest.
@MainActor
struct NameSpeakersView: View {
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var samplePlayer = VoiceSamplePlayer()
    @State private var renameRow: MeetingVoiceRow?
    @State private var renameText = ""
    @State private var errorMessage: String?
    /// Voices the user named or confirmed here. Only these teach the voice profiles.
    @State private var confirmedLabels = Set<String>()

    private var voices: [MeetingVoiceRow] {
        MeetingPeopleEditor.voices(in: meeting, record: store.record(for: meeting.id))
    }

    private var namedCount: Int {
        voices.filter { $0.assignedPersonID != nil }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Who said what?").font(.title.bold())
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if voices.isEmpty {
                        Text("No separate voices were detected in this recording.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(voices) { row in
                        voiceCard(row)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button {
                    samplePlayer.stop()
                    dismiss()
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.manentAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Name This Voice", isPresented: Binding(
                get: { renameRow != nil }, set: { if !$0 { renameRow = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameRow = nil }
                Button("Save") {
                    if let row = renameRow {
                        run {
                            try MeetingPeopleEditor.rename(row, to: renameText, meeting: meeting, context: context, store: store)
                            confirmedLabels.insert(row.label)
                        }
                    }
                    renameRow = nil
                }
            }
            .recordErrorAlert("Could Not Update People", message: $errorMessage)
            .onDisappear {
                samplePlayer.stop()
                let labels = confirmedLabels
                guard !labels.isEmpty else { return }
                let meeting = meeting
                Task { await SpeakerVoiceNaming.learn(labels: labels, meeting: meeting) }
            }
            .onChange(of: samplePlayer.errorMessage) { _, message in
                guard let message else { return }
                errorMessage = message
                samplePlayer.errorMessage = nil
            }
        }
    }

    private var subtitle: String {
        "\(namedCount) of \(voices.count) voices named. Names come from the meeting\u{2019}s people and what the minutes heard."
    }

    private func voiceCard(_ row: MeetingVoiceRow) -> some View {
        let audioURL = meeting.resolvedAudioFileURL
        return VStack(alignment: .leading, spacing: 10) {
            MeetingVoiceCard(
                row: row,
                displayName: displayName(row),
                stats: MeetingVoiceSamples.stats(for: row, in: meeting),
                samples: MeetingVoiceSamples.samples(for: row, in: meeting),
                canPlay: audioURL != nil,
                player: samplePlayer,
                onToggle: { sample in
                    guard let audioURL else { return }
                    samplePlayer.toggle(sample, audioURL: audioURL)
                },
                assignMenu: { voiceMenu(row) }
            )
            if matchedByVoice(row) {
                Label("Matched by voice. Change it from the name menu if it is wrong.", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            chips(for: row)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func chips(for row: MeetingVoiceRow) -> some View {
        let likely = likelyPerson(row)
        let people = meeting.namedAttendees.filter { $0.id != row.assignedPersonID && $0.id != likely?.id }
        let peopleNames = Set(meeting.namedAttendees.map { $0.name.lowercased() })
        let suggestions = NameSpeakerSuggestion.parse(meeting.offlineAnalysisData)
            .filter { !peopleNames.contains($0.name.lowercased()) && $0.name.lowercased() != likely?.name.lowercased() }
        if likely != nil || !people.isEmpty || !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let likely {
                        chip("\(likely.displayName) (likely)", systemImage: "waveform") {
                            run {
                                try MeetingPeopleEditor.assign(row, to: likely, meeting: meeting, context: context, store: store)
                                confirmedLabels.insert(row.label)
                            }
                        }
                        .accessibilityHint("Sounds like \(likely.displayName). Tap to confirm.")
                    }
                    ForEach(people, id: \.id) { person in
                        chip(person.name, systemImage: nil) {
                            run {
                                try MeetingPeopleEditor.assign(row, to: person, meeting: meeting, context: context, store: store)
                                confirmedLabels.insert(row.label)
                            }
                        }
                    }
                    ForEach(suggestions) { suggestion in
                        chip(suggestion.name, systemImage: "sparkles") {
                            run {
                                try MeetingPeopleEditor.rename(row, to: suggestion.name, meeting: meeting, context: context, store: store)
                                confirmedLabels.insert(row.label)
                            }
                        }
                        .accessibilityHint(suggestion.reason.isEmpty ? "Suggested from the minutes" : suggestion.reason)
                    }
                }
            }
        }
    }

    private func chip(_ title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(Theme.Colors.manentAccent)
            .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func voiceMenu(_ row: MeetingVoiceRow) -> some View {
        let assigned = meeting.namedAttendees.first(where: { $0.id == row.assignedPersonID })
        let likely = likelyPerson(row)
        let title = assigned?.displayName ?? likely.map { "\($0.displayName) (likely)" } ?? "Choose name"
        return Menu {
            if row.assignedPersonID != nil {
                Button("Keep as Unknown") {
                    run {
                        try MeetingPeopleEditor.keepUnknown(row, meeting: meeting, context: context, store: store)
                        confirmedLabels.remove(row.label)
                    }
                }
            }
            Button("Someone else\u{2026}", systemImage: "plus") {
                renameText = assigned?.name ?? ""
                renameRow = row
            }
            let others = voices.filter { $0.id != row.id }
            if !others.isEmpty {
                Menu("Merge Into", systemImage: "arrow.triangle.merge") {
                    ForEach(others) { other in
                        Button(displayName(other)) {
                            run {
                                try MeetingPeopleEditor.merge(row, into: other, meeting: meeting, context: context, store: store)
                                confirmedLabels.remove(row.label)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.footnote)
            }
            .foregroundStyle(Theme.Colors.manentAccent)
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Name \(row.label)")
        .accessibilityValue(assigned?.displayName ?? likely.map { "Likely \($0.displayName)" } ?? "Not named")
    }

    private func voiceMatch(_ row: MeetingVoiceRow) -> VoiceMatch? {
        SpeakerVoiceNaming.match(forLabel: row.label, meetingID: meeting.id)
    }

    /// The person a voice sounds like, offered when the engine was not sure enough to name it.
    private func likelyPerson(_ row: MeetingVoiceRow) -> Speaker? {
        guard row.assignedPersonID == nil, let match = voiceMatch(row), match.status == .suggested,
              !voices.contains(where: { $0.assignedPersonID == match.personID }) else { return nil }
        return SpeakerVoiceNaming.person(id: match.personID, context: context)
    }

    /// True while a voice still carries the name the engine gave it and the user has not changed it.
    private func matchedByVoice(_ row: MeetingVoiceRow) -> Bool {
        guard let match = voiceMatch(row), match.status == .auto,
              row.assignedPersonID == match.personID, !confirmedLabels.contains(row.label) else { return false }
        return true
    }

    private func displayName(_ row: MeetingVoiceRow) -> String {
        for person in meeting.namedAttendees where person.id == row.assignedPersonID { return person.name }
        return row.label
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
