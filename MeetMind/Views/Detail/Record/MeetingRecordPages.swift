import SwiftUI

/// "Decisions" segment: one row per decision with the person who decided it, plus add and delete.
/// Rows read `MeetingMinutesContent`, so they match the Minutes tab and the exports.
@MainActor
struct MeetingDecisionsList: View {
    let viewModel: MeetingDetailViewModel
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var composing = false
    @State private var errorMessage: String?

    var body: some View {
        let content = viewModel.minutesContent
        let decisions = content?.decisions ?? []
        let hasMinutes = viewModel.summary != nil
        List {
            Section {
                Button {
                    composing = true
                } label: {
                    Label("Add Decision", systemImage: "plus.circle.fill")
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(!hasMinutes)
            } footer: {
                if !hasMinutes { Text("Decisions can be added once the minutes are ready.") }
            }
            Section("Decisions") {
                if decisions.isEmpty {
                    Text("No decisions recorded.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(decisions) { decision in
                    NavigationLink {
                        MeetingDecisionDetail(viewModel: viewModel, index: decision.index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(decision.text).font(.subheadline)
                            if let name = decision.decidedBy {
                                Text("Decided by \(name)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(decision.index) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $composing) {
            if let meeting = viewModel.meeting {
                MeetingDecisionEditSheet(
                    title: "New Decision",
                    people: MeetingPeopleEditor.ownerChoices(for: meeting),
                    initialText: "",
                    initialDecider: nil,
                    onSave: { text, decider in
                        try MeetingRecordEditor.addDecision(text, decidedBy: decider, meeting: meeting,
                                                            context: context, store: store)
                    },
                    onDelete: nil
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .recordErrorAlert("Could Not Update Decisions", message: $errorMessage)
    }

    private func delete(_ index: Int) {
        guard let meeting = viewModel.meeting else { return }
        do {
            try MeetingRecordEditor.deleteDecision(at: index, meeting: meeting, context: context, store: store)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
/// "Transcript and audio" page pushed from the meeting options menu.
struct MeetingTranscriptAudioPage: View {
    let viewModel: MeetingDetailViewModel
    @Binding var searchText: String
    let onReassign: (TranscriptSegment) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MeetingTranscriptTabView(
                segments: viewModel.transcriptSegments,
                activeSegmentId: viewModel.activeSegmentId,
                searchText: $searchText,
                onSeek: { viewModel.tapToSeek(segment: $0) },
                onEdit: { viewModel.beginEditingTranscript(segment: $0) },
                onReassign: onReassign
            )
            if let duration = viewModel.meeting?.duration, duration > 0 {
                StickyAudioPlayerBar(
                    currentTime: viewModel.currentPlayheadTime,
                    totalDuration: duration,
                    isPlaying: viewModel.isPlaying,
                    playbackRate: viewModel.playbackRate,
                    onTogglePlayPause: { viewModel.togglePlayPause() },
                    onSeek: { viewModel.seek(to: $0) },
                    onSkipBackward: { viewModel.seek(to: max(0, viewModel.currentPlayheadTime - 15)) },
                    onSkipForward: { viewModel.seek(to: min(duration, viewModel.currentPlayheadTime + 15)) },
                    onCycleRate: { cyclePlaybackRate() }
                )
            }
        }
        .navigationTitle("Transcript and audio")
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { viewModel.stopPlayback() }
    }

    private func cyclePlaybackRate() {
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]
        let current = viewModel.playbackRate
        if let idx = rates.firstIndex(where: { abs($0 - current) < 0.05 }) {
            viewModel.setPlaybackRate(rates[(idx + 1) % rates.count])
        } else {
            viewModel.setPlaybackRate(1.0)
        }
    }
}
