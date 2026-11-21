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
/// "Transcript and audio" page: sticky audio player, transcript grouped by speaker turn, the playing line
/// highlighted and scrolled into view, search with highlighted matches.
struct MeetingTranscriptAudioPage: View {
    let viewModel: MeetingDetailViewModel
    @Binding var searchText: String
    let onReassign: (TranscriptSegment) -> Void
    @State private var playhead: TimeInterval = 0
    @State private var isPlaying = false
    @State private var rate: Float = 1.0
    /// The page owns the live query so search also works when a caller passes `.constant("")`.
    @State private var query = ""

    private var segments: [TranscriptSegment] { viewModel.transcriptSegments }

    private var hasAudio: Bool { viewModel.meeting?.resolvedAudioFileURL != nil }

    private var activeSegmentID: UUID? {
        guard isPlaying || playhead > 0 else { return nil }
        return TranscriptTurnGrouper.activeSegmentID(at: playhead, in: segments)
    }

    private var emptyKind: TranscriptEmptyKind {
        guard let meeting = viewModel.meeting else { return .notAvailable }
        if meeting.status == .processing, meeting.analysisState != "failed" { return .processing }
        return .notAvailable
    }

    var body: some View {
        MeetingTranscriptTabView(
            segments: segments,
            activeSegmentId: activeSegmentID,
            searchText: $query,
            emptyKind: emptyKind,
            onSeek: { viewModel.tapToSeek(segment: $0) },
            onEdit: { viewModel.beginEditingTranscript(segment: $0) },
            onReassign: onReassign
        )
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { playerArea }
        .navigationTitle("Transcript and audio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .tint(Theme.Colors.manentAccent)
        .onAppear { query = searchText }
        .onChange(of: query) { _, newValue in searchText = newValue }
        .task {
            while !Task.isCancelled {
                syncPlayback()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
        }
        .onDisappear { viewModel.stopPlayback() }
        .alert("Audio Not Available", isPresented: Binding(
            get: { viewModel.isShowingAudioMissingAlert },
            set: { viewModel.isShowingAudioMissingAlert = $0 }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The recording for this meeting is not on this iPhone, so lines cannot be played.")
        }
    }

    @ViewBuilder
    private var playerArea: some View {
        let duration = viewModel.totalDuration
        if hasAudio, duration > 0 {
            StickyAudioPlayerBar(
                currentTime: playhead,
                totalDuration: duration,
                isPlaying: isPlaying,
                playbackRate: rate,
                onTogglePlayPause: {
                    viewModel.togglePlayPause()
                    syncPlayback()
                },
                onSeek: {
                    viewModel.seek(to: $0)
                    syncPlayback()
                },
                onSkipBackward: {
                    viewModel.seek(to: max(0, viewModel.currentPlayheadTime - 15))
                    syncPlayback()
                },
                onSkipForward: {
                    viewModel.seek(to: min(duration, viewModel.currentPlayheadTime + 15))
                    syncPlayback()
                },
                onCycleRate: {
                    viewModel.setPlaybackRate(StickyAudioPlayerBar.nextRate(after: viewModel.playbackRate))
                    syncPlayback()
                }
            )
        } else {
            Label("No recording is saved for this meeting.", systemImage: "waveform.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }

    private func syncPlayback() {
        viewModel.refreshPlaybackPosition()
        playhead = viewModel.currentPlayheadTime
        isPlaying = viewModel.isPlaying
        rate = viewModel.playbackRate
    }
}