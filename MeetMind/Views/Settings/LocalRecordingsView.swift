import SwiftUI
import SwiftData

/// Saved recordings on this iPhone (Figma 605:1723).
/// Deleting here removes only the audio file; the meeting, transcript and minutes stay.
public struct LocalRecordingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    @State private var pendingDeletion: Meeting?
    @State private var errorMessage: String?

    public init() {}

    private var recordings: [(meeting: Meeting, file: LocalRecordingFile)] {
        var rows: [(meeting: Meeting, file: LocalRecordingFile)] = []
        for meeting in meetings {
            guard let url = meeting.resolvedAudioFileURL else { continue }
            let file = LocalRecordingFile(
                id: meeting.id, title: meeting.title, date: meeting.createdAt,
                duration: meeting.duration, bytes: LocalRecordingStorage.fileSize(at: url), url: url)
            rows.append((meeting, file))
        }
        return rows
    }

    public var body: some View {
        let rows = recordings
        let total = LocalRecordingStorage.totalBytes(rows.map(\.file))
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No Local Recordings",
                    systemImage: "waveform",
                    description: Text("Recordings you make or import are saved on this iPhone and listed here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    storageCard(total: total)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(rows, id: \.file.id) { row in
                        NavigationLink {
                            RecordingPlayerView(meeting: row.meeting)
                        } label: {
                            HStack(spacing: 12) {
                                dateTile(row.file.date)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.file.title).font(.subheadline)
                                    Text(subtitle(for: row.file)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete Audio", role: .destructive) { pendingDeletion = row.meeting }
                        }
                    }
                } header: {
                    Text("Saved Recordings")
                } footer: {
                    Text("\(rows.count) \(rows.count == 1 ? "recording" : "recordings") · \(LocalRecordingStorage.formatted(bytes: total)) on this iPhone. Swipe a recording to delete its audio and keep the minutes.")
                }
            }
        }
        .navigationTitle("Local Recordings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import Audio") { appState?.presentSheet(.audioImport) }
                    .disabled(appState == nil)
            }
        }
        .confirmationDialog(
            "Delete this recording's audio?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { meeting in
            Button("Delete Audio", role: .destructive) { deleteAudio(of: meeting) }
            Button("Cancel", role: .cancel) {}
        } message: { meeting in
            Text("The audio file for \"\(meeting.title)\" is removed from this iPhone. The meeting, transcript, minutes and tasks stay. This cannot be undone.")
        }
        .alert("Could not delete audio", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func storageCard(total: Int64) -> some View {
        let capacity = deviceCapacityBytes()
        let fraction = capacity > 0 ? min(1, Double(total) / Double(capacity)) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LocalRecordingStorage.formatted(bytes: total)).font(.title2.bold())
                if capacity > 0 {
                    Text("of \(LocalRecordingStorage.formatted(bytes: capacity)) on this iPhone")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction)
                .tint(Theme.Colors.manentAccent)
            Text("Audio kept for your meetings. Minutes, decisions and actions are kept when audio is deleted.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func dateTile(_ date: Date) -> some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.red)
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(.semibold))
        }
        .frame(width: 38, height: 38)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func deviceCapacityBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    private func subtitle(for file: LocalRecordingFile) -> String {
        let date = file.date.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(date) · \(LocalRecordingStorage.formatted(duration: file.duration)) · \(LocalRecordingStorage.formatted(bytes: file.bytes))"
    }

    private func deleteAudio(of meeting: Meeting) {
        pendingDeletion = nil
        if let url = meeting.resolvedAudioFileURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        meeting.setAudioFileURL(nil)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
