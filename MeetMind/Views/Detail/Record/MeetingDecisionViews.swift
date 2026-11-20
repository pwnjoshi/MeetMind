import SwiftUI
import SwiftData
import OfflineEngineKit

/// "Decision detail": the decision, how it was decided, who decided it and where it came from.
@MainActor
struct MeetingDecisionDetail: View {
    let viewModel: MeetingDetailViewModel
    let index: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var store = MeetingRecordStore.shared
    @State private var editing = false
    @State private var saveError: String?
    @State private var playingTurnID: String?

    private var decision: String? {
        guard let summary = viewModel.summary, summary.keyDecisions.indices.contains(index) else { return nil }
        return summary.keyDecisions[index]
    }

    var body: some View {
        ScrollView {
            if let meeting = viewModel.meeting, let decision {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(meeting.title) · \((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.day().month(.abbreviated))) · Decision")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(decision).font(.title.bold())
                    Text("Agreed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.24))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.2), in: Capsule())
                    evidenceSection(meeting: meeting, decision: decision)
                    deciderSection(meeting: meeting)
                    historySection(meeting: meeting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else {
                ContentUnavailableView("Decision Unavailable", systemImage: "doc.text")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if decision != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                        .foregroundStyle(Theme.Colors.manentAccent)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let decision {
                MeetingDecisionEditSheet(initialText: decision, onSave: saveDecision, onDelete: deleteDecision)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("Could Not Update Decision", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onDisappear { viewModel.stopPlayback() }
    }

    @ViewBuilder
    private func evidenceSection(meeting: Meeting, decision: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How It Was Decided").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            let moments = Self.moments(for: decision, in: meeting)
            if moments.isEmpty {
                Text("No supporting quotes were captured for this decision.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moments.enumerated()), id: \.offset) { entry in
                        momentRow(entry.element, meeting: meeting)
                        if entry.offset < moments.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    private func momentRow(_ moment: DecisionMoment, meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: moment.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(moment.speaker) · \(moment.timeText)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text("“\(moment.quote)”").textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if meeting.resolvedAudioFileURL != nil {
                let isPlaying = playingTurnID == moment.turnID && viewModel.isPlaying
                Button { togglePlay(moment) } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.manentAccent.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause supporting audio" : "Play supporting audio")
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
    }

    private func deciderSection(meeting: Meeting) -> some View {
        let record = store.record(for: meeting.id)
        let currentID = record.decider(at: index)
        let people = meeting.namedAttendees
        let current = people.first(where: { $0.id == currentID })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Decided By").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            Menu {
                ForEach(people, id: \.id) { person in
                    Button {
                        setDecider(person.id, meeting: meeting)
                    } label: {
                        if person.id == currentID {
                            Label(person.name, systemImage: "checkmark")
                        } else {
                            Text(person.name)
                        }
                    }
                }
                if currentID != nil {
                    Divider()
                    Button("Clear", role: .destructive) { setDecider(nil, meeting: meeting) }
                }
            } label: {
                HStack {
                    Text(current?.name ?? "Not set").foregroundStyle(current == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
            }
            .disabled(people.isEmpty)
        }
    }

    private func historySection(meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recorded in the meeting")
                Text("\((meeting.scheduledStartTime ?? meeting.createdAt).formatted(.dateTime.day().month(.abbreviated))) · from the transcript")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func setDecider(_ id: UUID?, meeting: Meeting) {
        do { try store.update(meeting.id) { $0.setDecider(id, at: index) } }
        catch { saveError = error.localizedDescription }
    }

    private func togglePlay(_ moment: DecisionMoment) {
        if playingTurnID == moment.turnID && viewModel.isPlaying {
            viewModel.stopPlayback()
            playingTurnID = nil
        } else {
            viewModel.seek(to: moment.start)
            if !viewModel.isPlaying { viewModel.togglePlayPause() }
            playingTurnID = moment.turnID
        }
    }

    private func saveDecision(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let summary = viewModel.summary, summary.keyDecisions.indices.contains(index) else { return }
        let previous = summary.keyDecisions
        summary.keyDecisions[index] = trimmed
        do {
            try context.save()
            editing = false
        } catch {
            summary.keyDecisions = previous
            saveError = error.localizedDescription
        }
    }

    private func deleteDecision() {
        guard let meeting = viewModel.meeting, let summary = viewModel.summary,
              summary.keyDecisions.indices.contains(index) else { return }
        let previous = summary.keyDecisions
        summary.keyDecisions.remove(at: index)
        do {
            try context.save()
            try? store.update(meeting.id) { $0.removeDecision(at: index) }
            editing = false
            dismiss()
        } catch {
            summary.keyDecisions = previous
            saveError = error.localizedDescription
        }
    }

    struct DecisionMoment {
        let turnID: String
        let speaker: String
        let start: TimeInterval
        let quote: String
        let colorHex: String
        var timeText: String { String(format: "%02d:%02d", Int(start) / 60, Int(start) % 60) }
    }

    static func moments(for decision: String, in meeting: Meeting) -> [DecisionMoment] {
        guard let result = meeting.offlineAnalysis,
              let point = result.analysis.lazy.flatMap(\.decisions).first(where: { $0.text == decision }) else { return [] }
        var moments: [DecisionMoment] = []
        for source in point.evidence {
            guard let turn = result.turns.first(where: { $0.id == source.turnID }) else { continue }
            let name = turn.speaker ?? "Speaker"
            let color = meeting.participants.first(where: { $0.name == name })?.avatarColorHex ?? "#4F46E5"
            moments.append(DecisionMoment(turnID: turn.id, speaker: name, start: turn.start, quote: source.quote, colorHex: color))
        }
        return moments
    }
}

/// "Edit Decision" sheet with a text field and Delete Decision.
struct MeetingDecisionEditSheet: View {
    let initialText: String
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var confirmDelete = false

    init(initialText: String, onSave: @escaping (String) -> Void, onDelete: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .accessibilityLabel("Decision")
                        if text.isEmpty {
                            Text("Decision").foregroundStyle(.tertiary)
                                .padding(.horizontal, 17).padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 120)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    Button("Delete Decision", role: .destructive) { confirmDelete = true }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Edit Decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { onSave(text) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this decision?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Decision", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
