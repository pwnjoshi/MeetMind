import SwiftUI

/// "Decisions" segment: one row per decision, with the person who decided it when the user set one.
@MainActor
struct MeetingDecisionsList: View {
    let viewModel: MeetingDetailViewModel
    @State private var store = MeetingRecordStore.shared

    var body: some View {
        let decisions = viewModel.summary?.keyDecisions ?? []
        let record = viewModel.meeting.map { store.record(for: $0.id) } ?? MeetingRecordData()
        List {
            if decisions.isEmpty {
                Text("No decisions recorded").foregroundStyle(.secondary)
            }
            ForEach(Array(decisions.enumerated()), id: \.offset) { entry in
                NavigationLink {
                    MeetingDecisionDetail(viewModel: viewModel, index: entry.offset)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.element)
                        if let name = deciderName(record.decider(at: entry.offset)) {
                            Text("Decided by \(name)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deciderName(_ id: UUID?) -> String? {
        guard let id, let meeting = viewModel.meeting else { return nil }
        return meeting.participants.first(where: { $0.id == id })?.name
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
