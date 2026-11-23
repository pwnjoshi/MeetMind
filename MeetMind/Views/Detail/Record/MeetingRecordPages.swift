import SwiftUI
import OfflineEngineKit

/// "Decisions" segment: one row per decision with the resolution, a status chip and who decided it and when.
/// Rows read `MeetingMinutesContent`, so they match the Minutes tab and the exports.
@MainActor
struct MeetingDecisionsList: View {
    let viewModel: MeetingDetailViewModel
    @Environment(\.modelContext) private var context
    @State private var store = MeetingRecordStore.shared
    @State private var composing = false

    var body: some View {
        let content = viewModel.minutesContent
        let decisions = content?.decisions ?? []
        let hasMinutes = viewModel.summary != nil
        let analysis = viewModel.meeting?.offlineAnalysis
        VStack(alignment: .leading, spacing: 12) {
            if decisions.isEmpty {
                Text("No decisions were recorded.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .recordCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(decisions) { decision in
                        row(decision, analysis: analysis)
                        Divider().padding(.leading, 16)
                    }
                    addButton(enabled: hasMinutes)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            if decisions.isEmpty {
                addButton(enabled: hasMinutes)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            if !hasMinutes {
                Text("Decisions can be added once the minutes are ready.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
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
    }

    private func addButton(enabled: Bool) -> some View {
        Button {
            composing = true
        } label: {
            Label("Add Decision", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? Theme.Colors.manentAccent : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func decidedLine(_ decision: MeetingMinutesContent.Decision, time: TimeInterval?) -> String? {
        if let name = decision.decidedBy, let time {
            return "Decided by \(name) \u{00B7} \(MeetingEvidence.clock(time))"
        }
        if let name = decision.decidedBy { return "Decided by \(name)" }
        if let time { return "At \(MeetingEvidence.clock(time)) in the recording" }
        return nil
    }

    private func row(_ decision: MeetingMinutesContent.Decision, analysis: MeetingAnalysisCheckpoint?) -> some View {
        let status = MeetingEvidence.status(of: decision.text, in: analysis)
        let time = MeetingEvidence.firstTime(of: MeetingEvidence.decision(decision.text, in: analysis), in: analysis)
        let line = decidedLine(decision, time: time)
        return NavigationLink {
            MeetingDecisionDetail(viewModel: viewModel, index: decision.index)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(decision.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    RecordChip(title: status.title, tint: status.tint)
                    if let line {
                        Text(line).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the decision")
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
