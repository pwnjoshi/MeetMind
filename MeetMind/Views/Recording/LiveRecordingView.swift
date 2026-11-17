import SwiftUI
import SwiftData

/// Master live recording console HUD coordinating waveforms, speech stream, and tool dock
public struct LiveRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @State private var viewModel: LiveRecordingViewModel
    @State private var isPhotoSheetPresented: Bool = false
    public let meetingId: UUID
    
    public init(meetingId: UUID, viewModel: LiveRecordingViewModel? = nil) {
        self.meetingId = meetingId
        self._viewModel = State(initialValue: viewModel ?? LiveRecordingViewModel(meetingId: meetingId))
    }
    
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            LiveRecordingHeaderView(
                title: $viewModel.meetingTitle,
                isOfflineFallback: viewModel.hasOfflineIndicatorPill,
                onDismiss: { dismiss() }
            )
            LiveRecordingTimerBadgeView(
                formattedDuration: viewModel.formattedDuration,
                isRecording: viewModel.isRecording,
                audioRouteBadgeTitle: viewModel.audioRouteBadgeTitle
            )
            WaveformVisualizerView(
                levels: viewModel.waveformLevels,
                isRecording: viewModel.isRecording
            )
            LiveSpeakerSwitcherBar(
                speakers: viewModel.availableSpeakers,
                activeSpeakerName: viewModel.activeSpeaker?.name,
                onSelectSpeaker: { viewModel.switchActiveSpeaker(to: $0.name) },
                onAddSpeaker: { viewModel.addNewSpeaker(name: "Speaker \(viewModel.availableSpeakers.count + 1)") }
            )
            LiveTranscriptScrollView(
                segments: viewModel.finalTranscriptSegments,
                interimText: viewModel.interimTranscriptText
            )
            LiveActionToolDock(
                bookmarkCount: viewModel.bookmarks.count,
                isBookmarkHighlighted: viewModel.isBookmarkButtonHighlighted,
                notesCount: viewModel.notesCount,
                photosCount: viewModel.photosCount,
                onBookmarkTap: { viewModel.addBookmark() },
                onNoteTap: { viewModel.openNoteDock() },
                onPhotoTap: { isPhotoSheetPresented = true }
            )
            RecordingControlBarView(
                isPaused: viewModel.isPaused,
                onDiscard: { viewModel.requestDiscard() },
                onTogglePauseResume: { viewModel.isPaused ? viewModel.resume() : viewModel.pause() },
                onStop: { handleStop() }
            )
        }
        .padding(.horizontal, Spacing.sm)
        .background(Theme.Colors.background)
        .navigationBarHidden(true)
        .sheet(isPresented: $viewModel.isNoteSheetPresented) {
            LiveNoteTakingSheet(timestamp: viewModel.noteCaptureTimestamp) { viewModel.saveNote(text: $0) }
        }
        .sheet(isPresented: $isPhotoSheetPresented) {
            LiveMediaCaptureSheet(timestamp: viewModel.elapsedDuration) { viewModel.captureWhiteboardPhoto(data: $0) }
        }
        .alert("Discard Recording?", isPresented: $viewModel.isShowingDiscardAlert) {
            Button("Discard", role: .destructive) { viewModel.confirmDiscard(); dismiss() }
            Button("Cancel", role: .cancel) { viewModel.cancelDiscard() }
        } message: { Text("Are you sure you want to discard this recording? All audio and notes will be deleted.") }
        .alert("Short Recording", isPresented: $viewModel.isShowingShortRecordingAlert) {
            Button("Discard", role: .destructive) { viewModel.confirmDiscard(); dismiss() }
            Button("Save Anyway") { proceedToProcessing() }
        } message: { Text(viewModel.shortRecordingPrompt) }
        .alert("Recording unavailable", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .task {
            do {
                try viewModel.prepareSession(context: modelContext)
                if viewModel.recordingState == .idle { viewModel.startSession() }
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
        .onDisappear { viewModel.leaveSession() }
    }
    
    private func handleStop() {
        if viewModel.isDurationUnderThreshold(seconds: 3.0) {
            viewModel.requestStop()
        } else {
            proceedToProcessing()
        }
    }
    
    private func proceedToProcessing() {
        Task {
            do {
                _ = try await viewModel.finishSession()
                router.navigate(to: .meetingProcessing(id: meetingId), in: .home)
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
    }
}
