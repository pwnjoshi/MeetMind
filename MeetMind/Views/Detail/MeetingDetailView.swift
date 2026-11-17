import SwiftUI
import SwiftData

/// Master meeting cockpit displaying segmented tabs, audio synchronization, and action extraction
public struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State public var viewModel: MeetingDetailViewModel
    
    @State private var transcriptSearch: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var showAskAISheet: Bool = false
    @State private var showActionItemModal: Bool = false
    @State private var showPhotoModal: String? = nil
    @State private var showSpeakerReassign: TranscriptSegment? = nil
    
    public init(viewModel: MeetingDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            MeetingDetailHeaderView(
                title: viewModel.headerTitle,
                durationText: viewModel.headerDurationText,
                statusTitle: viewModel.statusBadgeTitle,
                onRename: { renameText = viewModel.headerTitle; showRenameAlert = true },
                onExport: { showExportSheet = true },
                onAskAI: { showAskAISheet = true },
                onDelete: { dismiss() }
            )
            MeetingDetailTabBarView(selectedTab: viewModel.selectedTab) { viewModel.selectTab($0) }
            
            MeetingDetailTabContentView(
                selectedTab: viewModel.selectedTab,
                summary: viewModel.summary,
                transcriptSegments: viewModel.transcriptSegments,
                activeSegmentId: viewModel.activeSegmentId,
                transcriptSearch: $transcriptSearch,
                actionItems: viewModel.actionItems,
                notes: viewModel.notes,
                onCopySummary: { UIPasteboard.general.string = viewModel.generateCopyableSummaryText() },
                onRegenerateSummary: { Task { _ = try? await viewModel.regenerateSummary() } },
                onSeekTranscript: { viewModel.tapToSeek(segment: $0) },
                onEditTranscript: { viewModel.beginEditingTranscript(segment: $0) },
                onReassignSpeaker: { showSpeakerReassign = $0 },
                onToggleAction: { viewModel.toggleActionItemCompletion($0) },
                onAddAction: { showActionItemModal = true },
                onAddNote: {},
                onSelectPhoto: { showPhotoModal = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
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
        .background(Theme.Colors.background.ignoresSafeArea())
        .modifier(MeetingDetailSheetsModifier(
            viewModel: viewModel,
            showExportSheet: $showExportSheet,
            showAskAISheet: $showAskAISheet,
            showRenameAlert: $showRenameAlert,
            renameText: $renameText
        ))
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
