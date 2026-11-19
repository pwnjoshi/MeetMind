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
        GeometryReader { proxy in
            VStack(spacing: 0) {
                recordingTopBar
                Text(viewModel.meetingTitle)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)

                Spacer(minLength: 24)

                recordingStatus
                Text(viewModel.formattedDuration)
                    .font(.system(size: timerSize, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.top, 14)
                    .accessibilityLabel("Recording duration")
                    .accessibilityValue(viewModel.formattedDuration)

                WaveformVisualizerView(
                    levels: viewModel.isPaused ? [] : viewModel.waveformLevels,
                    isRecording: viewModel.isRecording && !viewModel.isPaused,
                    showsBackground: false
                )
                .frame(height: 86)
                .padding(.top, 8)

                liveTranscriptCard(height: min(218, max(158, proxy.size.height * 0.27)))
                    .padding(.top, 8)

                Spacer(minLength: 20)
                recordingControls
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHidden(true)
        .sensoryFeedback(.success, trigger: viewModel.bookmarks.count)
        .disabled(isFinishing)
        .alert("Finish Recording?", isPresented: $isFinishConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Finish and Save") { proceedToProcessing() }
        } message: {
            Text("Your recording will be saved on this iPhone.")
        }
        .sheet(isPresented: $viewModel.isNoteSheetPresented) {
            LiveNoteTakingSheet(timestamp: viewModel.noteCaptureTimestamp) { viewModel.saveNote(text: $0) }
        }
        .sheet(isPresented: $isPhotoSheetPresented) {
            LiveMediaCaptureSheet(timestamp: viewModel.elapsedDuration) { viewModel.captureWhiteboardPhoto(data: $0) }
        }
        .sheet(isPresented: $viewModel.isShowingDiscardAlert) {
            ViewThatFits(in: .vertical) {
                deleteConfirmation
                ScrollView { deleteConfirmation }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(uiColor: .secondarySystemBackground))
            .preferredColorScheme(.dark)
        }
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
    
    private var recordingTopBar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.requestDiscard) {
                Image(systemName: "xmark")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete recording")

            Spacer()

            HStack(spacing: 0) {
                captureTool("Add live note", icon: "text.bubble") { viewModel.openNoteDock() }
                captureTool("Insert image", icon: "photo") { isPhotoSheetPresented = true }
            }
            .background(Color(hex: "#1D1D20"), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.75))
        }
        .frame(height: 50)
    }

    private var recordingStatus: some View {
        Label(
            viewModel.isPaused ? "Paused" : "Recording",
            systemImage: viewModel.isPaused ? "pause.fill" : "circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(viewModel.isPaused ? Color.orange : Theme.Colors.coralRed)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            (viewModel.isPaused ? Color.orange : Theme.Colors.coralRed).opacity(0.20),
            in: Capsule()
        )
        .accessibilityLabel(viewModel.isPaused ? "Recording paused" : "Recording in progress")
    }

    private func liveTranscriptCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live transcript")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("Live transcript", isOn: $showsLiveTranscript)
                    .labelsHidden()
                    .tint(.green)
                    .accessibilityLabel("Live transcript")
            }

            Group {
                if showsLiveTranscript {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.finalTranscriptSegments) { segment in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(segment.speakerName) · \(transcriptTimestamp(segment.startTime))")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                    Text(segment.text)
                                        .font(.body)
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !viewModel.interimTranscriptText.isEmpty {
                                Text(viewModel.interimTranscriptText)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.67))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if viewModel.finalTranscriptSegments.isEmpty && viewModel.interimTranscriptText.isEmpty {
                                Text("Listening for the conversation…")
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.58))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "text.bubble")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.58))
                        Text("Live transcript is off")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.76))
                        Text("Recording continues and the transcript can be created after you stop.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(height: height, alignment: .top)
        .background(Color(hex: "#1E1E20"), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var recordingControls: some View {
        HStack(spacing: 36) {
            Button { viewModel.addBookmark() } label: {
                Image(systemName: viewModel.isBookmarkButtonHighlighted ? "flag.fill" : "flag")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(viewModel.isBookmarkButtonHighlighted ? Theme.Colors.warmAmber : .white)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add bookmark at \(viewModel.formattedDuration)")
            .accessibilityValue("\(viewModel.bookmarks.count) bookmarks")

            Button { viewModel.isPaused ? viewModel.resume() : viewModel.pause() } label: {
                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 70, height: 70)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPaused ? "Resume recording" : "Pause recording")

            Button(action: handleStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.Colors.coralRed, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish recording")
        }
        .frame(maxWidth: .infinity)
    }

    private func captureTool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "#A9A2FF"))
                .frame(width: 46, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var deleteConfirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.title)
                .foregroundStyle(.red)
                .frame(width: 62, height: 62)
                .background(.red.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text("Delete This Recording?").font(.title3.bold())
            Text("You’ve recorded \(viewModel.formattedDuration) so far. Deleting is permanent. The audio won’t be saved anywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(role: .destructive) {
                viewModel.confirmDiscard()
                dismiss()
            } label: {
                Text("Yes, Delete")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(.red, in: Capsule())
            }
            .padding(.top, 12)
            Button(action: viewModel.cancelDiscard) {
                Text("No, Keep Recording")
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Color(hex: "#A9A2FF"))
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(20)
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
                if router.homePath.last == .liveRecording(id: meetingId) {
                    let record = NavigationDestination.meetingDetail(id: meetingId)
                    if router.homePath.dropLast().last == record {
                        router.homePath.removeLast()
                    } else {
                        router.homePath[router.homePath.count - 1] = record
                    }
                }
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
    }

    private func transcriptTimestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
