import SwiftUI
import SwiftData
import AVFoundation

/// Master live recording console HUD coordinating waveforms, speech stream, and tool dock
public struct LiveRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @State private var viewModel: LiveRecordingViewModel
    @State private var isPhotoSheetPresented: Bool = false
    @State private var isFinishConfirmationPresented = false
    @State private var isFinishing = false
    @State private var showsLiveTranscript = true
    public let meetingId: UUID
    
    public init(meetingId: UUID, viewModel: LiveRecordingViewModel? = nil) {
        self.meetingId = meetingId
        self._viewModel = State(initialValue: viewModel ?? LiveRecordingViewModel(meetingId: meetingId))
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: handleStop) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Finish recording")
                Spacer()
                HStack {
                    Button { viewModel.openNoteDock() } label: { Image(systemName: "text.bubble") }
                        .accessibilityLabel("Add note")
                    Button { isPhotoSheetPresented = true } label: { Image(systemName: "photo") }
                        .accessibilityLabel("Attach photo")
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
            Text(viewModel.meetingTitle).font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 20) {
                    Label(viewModel.isPaused ? "Paused" : "Recording",
                          systemImage: viewModel.isPaused ? "pause.fill" : "record.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(viewModel.isPaused ? .orange : .red)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background((viewModel.isPaused ? Color.orange : Color.red).opacity(0.15), in: Capsule())
                    Text(viewModel.formattedDuration).font(.system(size: 60, weight: .medium)).monospacedDigit()
                    if viewModel.isPaused {
                        Rectangle().fill(.secondary.opacity(0.5)).frame(height: 1)
                            .frame(height: 60)
                            .accessibilityLabel("Audio capture paused")
                    } else {
                        WaveformVisualizerView(levels: viewModel.waveformLevels, isRecording: viewModel.isRecording)
                    }
                    VStack(spacing: 16) {
                        Toggle("Live transcript", isOn: $showsLiveTranscript).font(.subheadline)
                        if showsLiveTranscript {
                            LiveTranscriptScrollView(segments: viewModel.finalTranscriptSegments,
                                interimText: viewModel.interimTranscriptText)
                                .frame(minHeight: 140, idealHeight: 180)
                        }
                        if viewModel.isBookmarkButtonHighlighted {
                            Label("Bookmarked", systemImage: "flag").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                }
            }
            HStack(spacing: 36) {
                Button { viewModel.addBookmark() } label: { Image(systemName: "flag").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("Bookmark")
                Button { viewModel.isPaused ? viewModel.resume() : viewModel.pause() } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2).foregroundStyle(.black).frame(width: 70, height: 70)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(viewModel.isPaused ? "Resume recording" : "Pause recording")
                Button(action: handleStop) {
                    Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 56, height: 56)
                        .background(.red, in: Circle())
                }
                .accessibilityLabel("Finish recording")
            }
            .padding(.bottom, 36)
        }
        .padding(.horizontal, 24)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHidden(true)
        .disabled(isFinishing)
        .alert("Finish Recording?", isPresented: $isFinishConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Finish") { proceedToProcessing() }
        } message: {
            Text("Your recording will be saved on this iPhone.")
        }
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
                try viewModel.prepareSession(context: modelContext, settings: settings)
                if viewModel.recordingState == .idle { viewModel.startSession() }
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
        .onDisappear { viewModel.leaveSession() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began, viewModel.isRecording {
                viewModel.handleAudioSessionInterruption(began: true)
            }
        }
    }
    
    private func handleStop() {
        if viewModel.isDurationUnderThreshold(seconds: 3.0) {
            viewModel.requestStop()
        } else {
            isFinishConfirmationPresented = true
        }
    }
    
    private func proceedToProcessing() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            defer { isFinishing = false }
            do {
                _ = try await viewModel.finishSession()
                router.navigate(to: .meetingProcessing(id: meetingId), in: .home)
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
    }
}
