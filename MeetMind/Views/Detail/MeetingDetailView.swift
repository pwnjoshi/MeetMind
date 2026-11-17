import SwiftUI
import SwiftData

/// Master meeting cockpit displaying segmented tabs, audio synchronization, and action extraction
public struct MeetingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @State public var viewModel: MeetingDetailViewModel
    
    @State private var transcriptSearch: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showExportSheet: Bool = false
    @State private var showAskAISheet: Bool = false
    @State private var showActionItemModal: Bool = false
    @State private var showPhotoModal: String? = nil
    @State private var showSpeakerReassign: TranscriptSegment? = nil
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var showNoteSheet = false
    
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
                onDelete: { showDeleteConfirmation = true }
            )
            MeetingDetailTabBarView(selectedTab: viewModel.selectedTab) { viewModel.selectTab($0) }
            if let meeting = viewModel.meeting, meeting.status == .scheduled || meeting.status == .processing {
                Button(meeting.status == .scheduled ? "Start recording" : "Process saved audio") {
                    if meeting.status == .scheduled {
                        meeting.status = .recording
                        do {
                            try modelContext.save()
                            router.navigate(to: .liveRecording(id: meeting.id), in: .home)
                        } catch { deletionError = error.localizedDescription }
                    } else {
                        router.navigate(to: .meetingProcessing(id: meeting.id), in: .home)
                    }
                }
                .buttonStyle(.borderedProminent).padding(.vertical, 8)
            }
            
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
                onAddNote: { showNoteSheet = true },
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
        .sheet(isPresented: $showActionItemModal) {
            ActionItemEditModal(onSave: { title, priority, dueDate, assignee in
                if let meeting = viewModel.meeting {
                    meeting.addActionItem(ActionItem(title: title, assigneeName: assignee, dueDate: dueDate, priority: priority))
                    do { try modelContext.save() } catch { deletionError = error.localizedDescription }
                }
                showActionItemModal = false
            }, onDismiss: { showActionItemModal = false })
        }
        .sheet(isPresented: $showNoteSheet) {
            LiveNoteTakingSheet(timestamp: viewModel.currentPlayheadTime) { text in
                if let meeting = viewModel.meeting {
                    meeting.addNote(Note(content: text, timestamp: viewModel.currentPlayheadTime))
                    do { try modelContext.save() } catch { deletionError = error.localizedDescription }
                }
                showNoteSheet = false
            }
        }
        .sheet(item: $showSpeakerReassign) { segment in
            SpeakerReassignSheet(availableSpeakers: viewModel.meeting?.participants ?? [], currentSpeaker: segment.speaker, onSelect: { speaker in
                viewModel.reassignSpeaker(segment: segment, newSpeaker: speaker)
                showSpeakerReassign = nil
            }, onDismiss: { showSpeakerReassign = nil })
        }
        .sheet(isPresented: Binding(get: { showPhotoModal != nil }, set: { if !$0 { showPhotoModal = nil } })) {
            if let path = showPhotoModal {
                WhiteboardDetailModal(photoPath: path, onDismiss: { showPhotoModal = nil })
            }
        }
        .task {
            while !Task.isCancelled {
                viewModel.refreshPlaybackPosition()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
        }
        .onDisappear { viewModel.stopPlayback() }
        .alert("Delete meeting?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                do { try viewModel.deleteMeeting(); dismiss() }
                catch { deletionError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the meeting, transcript, notes, and action items.") }
        .alert("Unable to delete", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("OK") { deletionError = nil }
        } message: { Text(deletionError ?? "") }
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
