import SwiftUI
import SwiftData
import AVFoundation

/// Master live recording console HUD coordinating waveforms, speech stream, and tool dock
public struct LiveRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @Environment(AppState.self) private var appState: AppState?
    @State private var viewModel: LiveRecordingViewModel
    @State private var isPhotoSheetPresented: Bool = false
    @State private var isFinishConfirmationPresented = false
    @State private var isFinishing = false
    @State private var isNotesOnlyPresented = false
    @State private var showsLiveTranscript = true
    @State private var showsMicrophonePrimer = false
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
                recoveryControls
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isNoteSheetPresented {
                LiveNoteComposeBar(
                    timestamp: viewModel.noteCaptureTimestamp,
                    onSave: { viewModel.saveNote(text: $0) },
                    onCancel: { viewModel.isNoteSheetPresented = false }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay {
            if showsMicrophonePrimer {
                MicrophonePermissionView(
                    onAllow: {
                        showsMicrophonePrimer = false
                        viewModel.startSession()
                    },
                    onNotNow: {
                        showsMicrophonePrimer = false
                        viewModel.isMicrophoneUnavailable = true
                    }
                )
            }
        }
        .onChange(of: viewModel.recordingState) { _, state in updateLiveActivity(state) }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHidden(true)
        .sensoryFeedback(.success, trigger: viewModel.bookmarks.count)
        .disabled(isFinishing)
        .alert("Finish Recording?", isPresented: $isFinishConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Finish") { proceedToProcessing() }
        } message: {
            Text("Your recording will be saved on this iPhone.")
        }
        .sheet(isPresented: $isPhotoSheetPresented) {
            LiveMediaCaptureSheet(timestamp: viewModel.elapsedDuration, onAttach: { data, caption in
                viewModel.captureWhiteboardPhoto(data: data, caption: caption)
            })
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
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isMicrophoneUnavailable },
            set: { if !$0 { viewModel.isMicrophoneUnavailable = false } }
        )) {
            MicrophoneUnavailableView(
                onBack: leaveWithoutRecording,
                onTryAgain: retryRecording,
                onTakeNotes: { isNotesOnlyPresented = true },
                onImportRecording: importRecording
            )
            .fullScreenCover(isPresented: $isNotesOnlyPresented) {
                NotesOnlyView(
                    existingMeeting: fetchMeeting(),
                    onBack: { isNotesOnlyPresented = false },
                    onSaved: { _ in
                        isNotesOnlyPresented = false
                        viewModel.isMicrophoneUnavailable = false
                        viewModel.errorMessage = nil
                        showMeetingDetail()
                    }
                )
            }
        }
        .alert("Recording unavailable", isPresented: Binding(
            get: {
                viewModel.errorMessage != nil
                    && !viewModel.isMicrophoneUnavailable
                    && viewModel.recordingState != .saveFailed
                    && viewModel.recordingState != .stoppedUnsaved
            },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .task {
            do {
                try viewModel.prepareSession(context: modelContext, settings: settings)
                if automaticallyStartsSession, viewModel.recordingState == .idle {
                    if AVAudioApplication.shared.recordPermission == .undetermined {
                        showsMicrophonePrimer = true
                    } else {
                        viewModel.startSession()
                    }
                }
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
        .onDisappear {
            if automaticallyStartsSession { viewModel.leaveSession() }
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
        let presentation: (title: String, icon: String, color: Color) = switch viewModel.recordingState {
        case .preparing: ("Preparing", "hourglass", Color.gray)
        case .paused: ("Paused", "pause.fill", .orange)
        case .interrupted: ("Interrupted", "exclamationmark.triangle.fill", .orange)
        case .stopping: ("Saving", "arrow.triangle.2.circlepath", .blue)
        case .stoppedUnsaved: ("Stopped, Not Saved", "externaldrive.badge.exclamationmark", .orange)
        case .saveFailed: ("Save Failed", "exclamationmark.circle.fill", .red)
        case .saved: ("Saved", "checkmark.circle.fill", .green)
        default: ("Recording", "circle.fill", Theme.Colors.coralRed)
        }
        return Label(presentation.title, systemImage: presentation.icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(presentation.color.opacity(0.20), in: Capsule())
            .accessibilityLabel(presentation.title)
    }

    @ViewBuilder
    private var recoveryControls: some View {
        if viewModel.recordingState == .saveFailed || viewModel.recordingState == .stoppedUnsaved {
            VStack(spacing: 8) {
                Text(viewModel.errorMessage ?? "The audio is still on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Retry Save") { retrySave() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.manentAccent)
            }
            .padding(.top, 8)
        } else if viewModel.recordingState == .interrupted {
            VStack(spacing: 8) {
                Text(viewModel.interruptionCanResume
                     ? "Audio was interrupted. Resume this recording or finish with the audio already captured."
                     : "Audio was interrupted. You can finish safely now; Resume appears when the audio session is available.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Resume") { viewModel.resumeSession() }
                        .disabled(!viewModel.interruptionCanResume)
                    Button("Finish") { proceedToProcessing() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }

    private func liveTranscriptCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Live transcript · Provisional")
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
            Text("You\u{2019}ve recorded \(recordedPhrase) so far. Deleting is permanent \u{2014} the audio won\u{2019}t be saved anywhere.")
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

    private func updateLiveActivity(_ state: RecordingState) {
        let controller = RecordingLiveActivityController.shared
        switch state {
        case .recording:
            controller.start(title: viewModel.meetingTitle, elapsed: viewModel.elapsedDuration)
            controller.update(isPaused: false, elapsed: viewModel.elapsedDuration)
        case .paused, .interrupted:
            controller.update(isPaused: true, elapsed: viewModel.elapsedDuration)
        case .stopping, .stopped, .stoppedUnsaved, .saveFailed, .saved, .idle:
            controller.end()
        case .preparing:
            break
        }
    }

    private func handleStop() {
        if viewModel.isDurationUnderThreshold(seconds: 3.0) {
            viewModel.requestStop()
        } else {
            isFinishConfirmationPresented = true
        }
    }
    
    private func retrySave() {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        do {
            _ = try viewModel.retrySave()
            viewModel.errorMessage = nil
            showMeetingDetail()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func proceedToProcessing() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            defer { isFinishing = false }
            do {
                _ = try await viewModel.finishSession()
                showMeetingDetail()
            } catch { viewModel.errorMessage = error.localizedDescription }
        }
    }

    /// Replaces the live recording route with the meeting record.
    private func showMeetingDetail() {
        guard router.homePath.last == .liveRecording(id: meetingId) else { return }
        let record = NavigationDestination.meetingDetail(id: meetingId)
        if router.homePath.dropLast().last == record {
            router.homePath.removeLast()
        } else {
            router.homePath[router.homePath.count - 1] = record
        }
    }

    private var recordedPhrase: String {
        let total = max(0, Int(viewModel.elapsedDuration.isFinite ? viewModel.elapsedDuration : 0))
        if total >= 60 {
            let minutes = total / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(total) second\(total == 1 ? "" : "s")"
    }

    private func fetchMeeting() -> Meeting? {
        let id = meetingId
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Removes the meeting only when nothing was written to it yet.
    private func discardIfEmpty() {
        viewModel.isMicrophoneUnavailable = false
        if let meeting = fetchMeeting(), meeting.notes.isEmpty, meeting.audioFileURL == nil,
           (meeting.agendaText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.confirmDiscard()
        }
    }

    private func leaveWithoutRecording() {
        discardIfEmpty()
        dismiss()
    }

    private func retryRecording() {
        if AVAudioApplication.shared.recordPermission == .denied { return }
        viewModel.isMicrophoneUnavailable = false
        viewModel.errorMessage = nil
        viewModel.startSession()
    }

    private func importRecording() {
        discardIfEmpty()
        dismiss()
        Task {
            // Let this screen finish leaving before the import sheet opens.
            try? await Task.sleep(for: .milliseconds(600))
            appState?.activeSheet = .audioImport
        }
    }

    private func transcriptTimestamp(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
