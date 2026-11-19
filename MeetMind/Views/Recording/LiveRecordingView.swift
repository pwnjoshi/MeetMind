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
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 60
    public let meetingId: UUID
    private let automaticallyStartsSession: Bool
    
    public init(
        meetingId: UUID,
        viewModel: LiveRecordingViewModel? = nil,
        automaticallyStartsSession: Bool = true,
        initiallyShowsFinishConfirmation: Bool = false
    ) {
        self.meetingId = meetingId
        self._viewModel = State(initialValue: viewModel ?? LiveRecordingViewModel(meetingId: meetingId))
        self.automaticallyStartsSession = automaticallyStartsSession
        self._isFinishConfirmationPresented = State(initialValue: initiallyShowsFinishConfirmation)
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: handleStop) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Finish recording")
                Spacer()
                ControlGroup {
                    Button { viewModel.openNoteDock() } label: { Image(systemName: "text.bubble") }
                        .accessibilityLabel("Add note")
                    Button { isPhotoSheetPresented = true } label: { Image(systemName: "photo") }
                        .accessibilityLabel("Attach photo")
                }
                .buttonStyle(.bordered).controlSize(.large)
                .fixedSize()
            }
            Text(viewModel.meetingTitle).font(.largeTitle.bold()).foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The recording console is a fixed, glanceable surface. Only the
            // transcript itself scrolls; the timer and capture controls never
            // drift away from the user's thumb while recording.
            VStack(spacing: 20) {
                    Label(viewModel.isPaused ? "Paused" : "Recording",
                          systemImage: viewModel.isPaused ? "pause.fill" : "record.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(viewModel.isPaused ? Color.orange : Color.red)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background((viewModel.isPaused ? Color.orange : Color.red).opacity(0.15), in: Capsule())
                    Text(viewModel.formattedDuration)
                        .font(.system(size: timerSize, weight: .medium)).monospacedDigit().foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel("Recording duration")
                        .accessibilityValue(viewModel.formattedDuration)
                    if viewModel.isPaused {
                        Rectangle().fill(.secondary.opacity(0.5)).frame(height: 1)
                            .frame(height: 60)
                            .accessibilityLabel("Audio capture paused")
                    } else {
                        WaveformVisualizerView(levels: viewModel.waveformLevels,
                            isRecording: viewModel.isRecording, showsBackground: false)
                    }
                    VStack(spacing: 16) {
                        Toggle("Live transcript", isOn: $showsLiveTranscript).font(.subheadline).foregroundStyle(.white).tint(.green)
                        if showsLiveTranscript {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(viewModel.finalTranscriptSegments) { segment in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(segment.speakerName) · \(transcriptTimestamp(segment.startTime))")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.72))
                                            Text(segment.text)
                                                .font(.body)
                                                .foregroundStyle(.white.opacity(0.94))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    if !viewModel.interimTranscriptText.isEmpty {
                                        Text(viewModel.interimTranscriptText)
                                            .font(.body)
                                            .foregroundStyle(.white.opacity(0.72))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(minHeight: 140, idealHeight: 180)
                            Text("Preview only — the final Hindi–English transcript is checked after recording.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.68))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if viewModel.isBookmarkButtonHighlighted {
                            Label("Bookmarked · \(viewModel.formattedDuration)", systemImage: "flag")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.16), in: Capsule())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                }
                .padding(20)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12)))
            }
            if !viewModel.bookmarks.isEmpty {
                HStack(spacing: 8) {
                    Label("\(viewModel.bookmarks.count) bookmarked", systemImage: "flag.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
                    Spacer(minLength: 8)
                    ForEach(Array(viewModel.bookmarks.suffix(3).reversed())) { bookmark in
                        Text(transcriptTimestamp(bookmark.timestamp))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(viewModel.bookmarks.count) bookmarks recorded")
            }
            HStack(spacing: 36) {
                Button { viewModel.addBookmark() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "flag.fill").font(.title3)
                        Text("Bookmark").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white).frame(width: 70, height: 58)
                    .background(Color.white.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("Add bookmark at \(viewModel.formattedDuration)")
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
        .statusBarHidden(true)
        .sensoryFeedback(.success, trigger: viewModel.bookmarks.count)
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
                if automaticallyStartsSession, viewModel.recordingState == .idle { viewModel.startSession() }
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
        .onDisappear {
            if automaticallyStartsSession { viewModel.leaveSession() }
        }
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

    private func transcriptTimestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
