import SwiftUI
import SwiftData
import OfflineEngineKit
import Darwin
import AVFoundation
import UserNotifications

/// Post-recording review and on-device minutes generation.
public struct MeetingProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsViewModel.self) private var settings
    @State private var showsVidur = false
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meetings: [Meeting]
    @State private var selectedSection = "Minutes"
    @State private var showsPeople = false
    @State private var showsRename = false
    @State private var meetingTitleDraft = ""
    @State private var preparingSpeakers = false
    @State private var showsReviewChecklist = false
    @State private var showsTranscript = false
    @State private var editingSegment: TranscriptSegment?
    @State private var transcriptDraft = ""
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlaying = false
    @State private var processingError: String?
    @State private var viewModel: ProcessingPipelineViewModel
    @State private var missingModels: [ModelProfile] = []
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var downloadProgress: Double = 0
    @State private var downloading = false
    @State private var checkingModels = false
    public let meetingId: UUID

    public init(meetingId: UUID, viewModel: ProcessingPipelineViewModel? = nil) {
        self.meetingId = meetingId
        self._viewModel = State(initialValue: viewModel ?? ProcessingPipelineViewModel(meetingId: meetingId))
    }

    public init(viewModel: ProcessingPipelineViewModel, meetingId: UUID? = nil) {
        self.meetingId = meetingId ?? UUID()
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    meetingTitleDraft = meeting?.title ?? ""
                    showsRename = true
                } label: {
                    Text(meeting?.title ?? "Quick meeting").font(.title.bold()).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .disabled(meeting == nil)
                .accessibilityHint("Rename this meeting")
                if let meeting {
                    Text(meeting.createdAt.formatted(date: .long, time: .shortened))
                        .font(.footnote).foregroundStyle(.secondary)
                    MeetingSeriesMenu(meeting: meeting) { processingError = $0 }
                    ProcessingPeopleRow(meeting: meeting) { showsPeople = true }
                }
                Picker("Meeting section", selection: $selectedSection) {
                    ForEach(["Minutes", "Actions", "Decisions"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    if busy || OfflineAnalysisBackgroundScheduler.status(for: meetingId) != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Processing Steps").font(.headline)
                        if let backgroundStatus = OfflineAnalysisBackgroundScheduler.status(for: meetingId), !busy {
                            Label(backgroundStatus, systemImage: "clock")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        let stageIsRunning = busy || OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId)
                        ForEach(Array(processingSteps.enumerated()), id: \.offset) { index, step in
                            Label(step, systemImage: index < activeStep ? "checkmark.circle.fill" :
                                  index == activeStep && stageIsRunning ? "circle.dotted" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(index < activeStep || (index == activeStep && stageIsRunning) ? Color.primary : Color.secondary)
                                .accessibilityValue(index < activeStep ? "Complete" :
                                                    index == activeStep && stageIsRunning ? "Current stage" : "Pending")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        if checkingModels {
                            Text("Verifying on-device models").font(.title3.bold())
                            ProgressView()
                            Text("Checking each required model before processing starts.").foregroundStyle(.secondary)
                        } else if busy {
                            Text(processingTitle).font(.title3.bold())
                            ProgressView(value: downloading ? downloadProgress : viewModel.overallProgress)
                            Text("Your audio is saved on this iPhone.").foregroundStyle(.secondary)
                            if preparingSpeakers {
                                Button("Pause speaker review") { operation?.cancel() }
                            } else {
                                Button("Keep in Background", systemImage: "clock") { queueAnalysis() }
                            }
                        } else if let backgroundStatus = OfflineAnalysisBackgroundScheduler.status(for: meetingId) {
                            Text(backgroundStatus).font(.title3.bold())
                            Text("Your audio is saved. You can leave and return to this meeting.")
                                .foregroundStyle(.secondary)
                        } else if viewModel.jobSnapshot?.state == .queued {
                            Text("Queued").font(.title3.bold())
                            Text("Your recording is saved and ready for on-device processing.")
                                .foregroundStyle(.secondary)
                            Button("Process Now") { start() }
                        } else if modelsRequired {
                            Text("Models Required").font(.title3.bold())
                            Text("Download or repair these on-device models before processing:")
                                .foregroundStyle(.secondary)
                            ForEach(viewModel.modelStatuses.filter { $0.readiness != .ready }) { status in
                                HStack {
                                    Text(status.profile.name)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: status.profile.downloadBytes, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                }
                                if case .corrupt(let reason) = status.readiness {
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("Total download: \(missingModelSize)")
                                .font(.subheadline.weight(.semibold))
                            Button("Download & Continue") { start(download: true) }
                                .buttonStyle(.borderedProminent)
                        } else if viewModel.jobSnapshot?.state == .paused {
                            Text("Processing paused").font(.title3.bold())
                            Text("Your recording and completed steps are saved.").foregroundStyle(.secondary)
                            Button("Retry") { start() }
                        } else if let failure = viewModel.jobSnapshot?.failure {
                            Text("Processing needs attention").font(.title3.bold())
                            Text(failure.message).foregroundStyle(.secondary)
                            recoveryButton(for: failure)
                        } else if viewModel.jobSnapshot?.state == .speakerReview || meeting?.analysisState == "speakerReview" {
                            Text("Speaker review").font(.title3.bold())
                            Text(viewModel.jobSnapshot?.warning ?? "Assign detected voices, or continue with unnamed speakers.")
                                .foregroundStyle(.secondary)
                            Button("Review Speakers") { showsPeople = true }
                        } else if isReadyForReview {
                            reviewSection
                        } else if selectedSection == "Minutes" {
                            if meeting?.analysisState == "failed" || meeting?.analysisState == "paused" {
                                Text(meeting?.analysisState == "failed" ? "Processing needs attention" : "Processing paused")
                                    .font(.title3.bold())
                                Text(processingError ?? "Your audio is saved. You can continue from the last completed step.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Who said what?").font(.title3.bold())
                                Text("Name the voices so the minutes show who decided what and who owns each action.")
                                    .foregroundStyle(.secondary)
                            }
                            if let meeting {
                                let rows = MeetingPeopleEditor.voices(in: meeting, record: MeetingRecordStore.shared.record(for: meeting.id))
                                Text("\(rows.count) detected voices · \(rows.filter { $0.assignedPersonID != nil }.count) named")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Button {
                                if meeting?.analysisState == "speakerReview" {
                                    showsPeople = true
                                } else {
                                    start(download: true, speakersOnly: true)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(meeting?.analysisState == "speakerReview" ? "Name Detected Voices" : "Detect Voices")
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }
                        } else {
                            Text("\(selectedSection) will appear after minutes are generated.").font(.headline)
                            if selectedSection == "Actions" {
                                Text("Review suggested actions before saving them.").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                }
                if selectedSection == "Minutes" {
                    Button { showsTranscript = true } label: {
                        HStack {
                            Text("Transcript and audio").font(.headline)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                if let processingError {
                    Text(processingError).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let meeting {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Vidur", systemImage: "sparkles") {
                        showsVidur = true
                    }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename Meeting", systemImage: "pencil") {
                            meetingTitleDraft = meeting.title
                            showsRename = true
                        }
                        Button("Show Transcript", systemImage: "doc.text") {
                            showsTranscript = true
                        }
                        .disabled(busy)
                    } label: {
                        Label("Meeting options", systemImage: "ellipsis").labelStyle(.iconOnly)
                    }
                }
            }
        }
        .tint(Theme.Colors.manentAccent)
        .safeAreaInset(edge: .bottom) {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let backgroundRunning = OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId)
                let queued = OfflineAnalysisBackgroundScheduler.status(for: meetingId) != nil
                    || viewModel.jobSnapshot?.state == .queued
                Button {
                    if isReadyForReview { showsReviewChecklist = true }
                    else { start(download: modelsRequired) }
                } label: {
                    Text(isReadyForReview ? "Review Checklist" :
                         (modelsRequired ? "Download & Continue" :
                          (queued && !backgroundRunning ? "Process Now" : "Generate Minutes")))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.manentAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(busy || checkingModels || backgroundRunning)
                .padding()
            }
        }
        .navigationDestination(isPresented: $showsVidur) {
            RootAskAISheet(meetingId: meetingId, modelContext: modelContext) { showsVidur = false }
        }
        .navigationDestination(isPresented: $showsReviewChecklist) {
            if let meeting { MinutesReviewChecklistView(meeting: meeting) }
        }
        .sheet(isPresented: $showsPeople) {
            if let meeting {
                MeetingPeopleSheet(
                    meeting: meeting,
                    viewModel: MeetingDetailViewModel(meeting: meeting, meetingId: meeting.id, modelContext: modelContext)
                )
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showsTranscript, onDismiss: {
            audioPlayer?.stop()
            audioPlayer = nil
            audioPlaying = false
        }) {
            NavigationStack {
                List {
                    if let url = meeting?.resolvedAudioFileURL {
                        Button(audioPlaying ? "Pause audio" : "Play audio",
                               systemImage: audioPlaying ? "pause.fill" : "play.fill") {
                            toggleSavedAudio(url)
                        }
                        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                            audioPlaying = audioPlayer?.isPlaying == true
                        }
                    }
                    Section("Transcript") {
                        if let segments = meeting?.transcriptSegments, !segments.isEmpty {
                            ForEach(segments.sorted { $0.startTime < $1.startTime }, id: \.id) { segment in
                                Button {
                                    transcriptDraft = segment.text
                                    editingSegment = segment
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(segment.speakerDisplayName) · \(segment.formattedStartTime)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(segment.text).foregroundStyle(.primary)
                                    }
                                }
                                .disabled(OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId))
                            }
                        } else {
                            ContentUnavailableView(
                                "Transcript Not Available",
                                systemImage: "doc.text.magnifyingglass",
                                description: Text(meeting?.analysisState == "failed"
                                    ? "Processing stopped before a transcript was saved. Retry processing from this meeting."
                                    : "The transcript will appear after on-device processing completes.")
                            )
                        }
                    }
                }
                .navigationTitle("Transcript and Audio")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsTranscript = false }
                    }
                }
                .alert("Edit Transcript", isPresented: Binding(
                    get: { editingSegment != nil }, set: { if !$0 { editingSegment = nil } }
                )) {
                    TextField("Transcript", text: $transcriptDraft)
                    Button("Cancel", role: .cancel) {}
                    Button("Save", action: saveTranscriptCorrection)
                        .disabled(transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert("Rename Meeting", isPresented: $showsRename) {
            TextField("Meeting title", text: $meetingTitleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveMeetingTitle() }
                .disabled(meetingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            viewModel.onNavigateToDetail = { id in
                OfflineAnalysisBackgroundScheduler.remove(meetingID: id)
            }
            // Opening this screen verifies local readiness but never starts a
            // model download or meeting analysis without an explicit tap.
            checkingModels = true
            Task { @MainActor in
                defer { checkingModels = false }
                do {
                    try viewModel.prepareForProduction(context: modelContext, settings: settings)
                    _ = try await viewModel.refreshAnalysisState()
                    processingError = viewModel.jobSnapshot?.failure?.message
                } catch {
                    processingError = (error as? AnalysisCoordinatorError)?.errorDescription
                        ?? (error as? AnalysisJobStoreError)?.errorDescription
                        ?? AnalysisFailure.stable(.processingFailed).message
                }
            }
        }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, busy {
                // Release the foreground lease at a checkpoint before enqueueing
                // the same durable job for an iOS processing window.
                let foregroundOperation = operation
                foregroundOperation?.cancel()
                if !preparingSpeakers {
                    Task { @MainActor in
                        if let foregroundOperation { await foregroundOperation.value }
                        OfflineAnalysisBackgroundScheduler.schedule(meetingID: meetingId)
                    }
                }
            }
        }
    }

    private var meeting: Meeting? { meetings.first { $0.id == meetingId } }

    private var modelsRequired: Bool {
        viewModel.modelStatuses.contains { $0.readiness != .ready }
    }

    private var missingModelSize: String {
        let bytes = viewModel.modelStatuses.filter { $0.readiness != .ready }
            .reduce(Int64(0)) { $0 + $1.profile.downloadBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private func recoveryButton(for failure: AnalysisFailure) -> some View {
        switch failure.recoveryAction {
        case .repairModels:
            Button("Repair Models") { start(download: true) }
        case .changeLanguage:
            Button("Change Language") { processingError = "Choose the recording language in Settings, then tap Retry." }
        case .openTranscript:
            Button("Open Transcript") { showsTranscript = true }
        case .processNow, .retry:
            Button("Retry") { start() }
        case .returnToMeetings:
            Button("Return to Meetings") { dismiss() }
        }
    }

    private var isReadyForReview: Bool {
        meeting?.analysisState == "completed" && meeting?.summary != nil
    }

    @ViewBuilder
    private var reviewSection: some View {
        switch selectedSection {
        case "Minutes":
            Text("Minutes ready for review").font(.title3.bold())
            if let summary = meeting?.summary {
                ForEach(Array(summary.keyPoints.prefix(4).enumerated()), id: \.offset) { _, point in
                    Text(point).font(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Review the transcript or name voices before finalizing.")
                .font(.subheadline).foregroundStyle(.secondary)
        case "Actions":
            let actions = meeting?.actionItems ?? []
            Text(actions.isEmpty ? "No action items found" : "Suggested actions").font(.title3.bold())
            if actions.isEmpty {
                Text("Minutes found no grounded commitments to turn into tasks.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(actions.prefix(4), id: \.id) { action in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title).font(.body.weight(.medium))
                        Text(action.assignee?.name ?? "Unassigned").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        default:
            let decisions = meeting?.summary?.keyDecisions ?? []
            Text(decisions.isEmpty ? "No decisions found" : "Decisions").font(.title3.bold())
            if decisions.isEmpty {
                Text("No explicit decision was found in this meeting.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(decisions.prefix(4).enumerated()), id: \.offset) { _, decision in
                    Text(decision).font(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detectedVoices(in meeting: Meeting) -> [Speaker] {
        meeting.participants.filter { $0.recordingVoiceLabel != nil }
    }

    private func saveTranscriptCorrection() {
        let text = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let segment = editingSegment, !text.isEmpty, text != segment.text,
              !OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId) else { return }
        let previous = (segment.text, segment.isEdited)
        segment.text = text
        segment.isEdited = true
        do { try modelContext.save() }
        catch {
            (segment.text, segment.isEdited) = previous
            processingError = error.localizedDescription
        }
    }

    private var processingSteps: [String] {
        let preparation = ["Prepare on-device models", "Create transcript", "Identify speakers"]
        return preparingSpeakers ? preparation : preparation + ["Generate minutes", "Save results"]
    }

    private var activeStep: Int {
        if downloading { return 0 }
        if !busy, OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId),
           OfflineAnalysisBackgroundScheduler.stage(for: meetingId) == nil { return 0 }
        if !busy, let stage = OfflineAnalysisBackgroundScheduler.stage(for: meetingId) {
            switch stage {
            case .transcription: return 1
            case .speakers: return 2
            case .analysis: return 3
            case .completed: return 4
            }
        }
        if busy {
            switch viewModel.currentStep {
            case .initial: return 0
            case .audio: return 1
            case .diarization: return 2
            case .summarization: return 3
            case .actions: return 4
            case .completed: return 5
            }
        }
        switch meeting?.analysisState {
        case "transcription": return 1
        case "speakers": return 2
        case "speakerReview", "analysis": return 3
        case "completed": return 5
        default: return -1
        }
    }

    private func saveMeetingTitle() {
        let title = meetingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let meeting, !title.isEmpty else { return }
        let previousTitle = meeting.title
        meeting.title = title
        do { try modelContext.save() }
        catch {
            meeting.title = previousTitle
            processingError = error.localizedDescription
        }
    }

    private var processingTitle: String {
        if viewModel.jobSnapshot?.state == .verifying { return "Verifying on-device models" }
        if downloading { return "Downloading on-device models" }
        switch viewModel.currentStep {
        case .initial: return "Preparing on-device models"
        case .audio: return "Creating transcript"
        case .diarization:
            // Windows transcribed while recording are reused, so the transcript
            // can already be complete when speaker identification begins.
            if let reuse = TranscriptReuseRegistry.shared.summary(for: meetingId) {
                if reuse.fullyReused { return "Transcript ready from recording \u{2014} identifying speakers" }
                if reuse.partiallyReused { return "Transcript ready \u{2014} identifying speakers" }
            }
            return "Identifying speakers"
        case .summarization: return "Creating minutes"
        case .actions, .completed: return "Saving results"
        }
    }



    private func toggleSavedAudio(_ url: URL) {
        do {
            if audioPlayer == nil { audioPlayer = try AVAudioPlayer(contentsOf: url) }
            guard let audioPlayer else { return }
            if audioPlayer.isPlaying {
                audioPlayer.pause()
                audioPlaying = false
            } else {
                audioPlaying = audioPlayer.play()
            }
        } catch {
            processingError = error.localizedDescription
            showsTranscript = false
        }
    }

    private func queueAnalysis() {
        let foregroundOperation = operation
        foregroundOperation?.cancel()
        Task { @MainActor in
            if let foregroundOperation { await foregroundOperation.value }
            OfflineAnalysisBackgroundScheduler.schedule(meetingID: meetingId)
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            dismiss()
        }
    }

    private func start(download: Bool = false, speakersOnly: Bool = false) {
        guard !busy else { return }
        guard !OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId) else {
            processingError = "This meeting is already running in the background. Follow its progress above."
            return
        }
        OfflineAnalysisBackgroundScheduler.remove(meetingID: meetingId)
        busy = true
        preparingSpeakers = speakersOnly
        processingError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer {
                busy = false
                preparingSpeakers = false
                downloading = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                try viewModel.prepareForProduction(context: modelContext, settings: settings)
                missingModels = try await viewModel.missingOfflineModels(speakersOnly: speakersOnly)
                if !missingModels.isEmpty {
                    guard download else { return }
                    downloading = true
                    downloadProgress = 0
                    try await viewModel.downloadAndContinueModels(speakersOnly: speakersOnly) { _, value in
                        Task { @MainActor in downloadProgress = value }
                    }
                    missingModels = try await viewModel.missingOfflineModels(speakersOnly: speakersOnly)
                    downloading = false
                }
                try Task.checkCancellation()
                if speakersOnly {
                    try await viewModel.prepareSpeakerReview()
                    showsPeople = true
                } else {
                    try await viewModel.startPipeline()
                }
            } catch is CancellationError {
                processingError = "Paused. Your audio, completed steps, and partial model downloads are saved. Tap Resume when you return."
            } catch {
                processingError = viewModel.jobSnapshot?.failure?.message
                    ?? (error as? AnalysisCoordinatorError)?.errorDescription
                    ?? (error as? AnalysisJobStoreError)?.errorDescription
                    ?? AnalysisFailure.stable(.processingFailed).message
            }
        }
    }
}

/// USB-triggered synthetic integration check. Uses a separate in-memory store;
/// never selects, reads, or exports a user's recording or meeting content.
@MainActor
struct OfflinePipelineSmokeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = "Synthetic offline pipeline check"
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Text("Synthetic integration test").font(.title2)
            Text(status)
            Text("Keep MeetMind open. This uses a public test clip and does not change your saved meetings.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
        .onAppear {
            guard operation == nil else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            operation = Task { @MainActor in
                defer { UIApplication.shared.isIdleTimerDisabled = false }
                let id = UUID()
                do {
                    guard let audio = OfflineBenchmarkRunner.syntheticAudioURL else {
                        throw OfflineError.unavailable("Synthetic audio is unavailable.")
                    }
                    let container = try ModelContainerFactory.createInMemoryContainer()
                    let context = container.mainContext
                    let meeting = Meeting(id: id, title: "Synthetic pipeline check", status: .processing, audioFileURL: audio)
                    context.insert(meeting)
                    try context.save()
                    let vm = ProcessingPipelineViewModel(meeting: meeting, modelContext: context)
                    vm.onOfflineStageChanged = { stage in
                        status = "Running: \(stage.rawValue)"
                        print("MEETMIND_PIPELINE stage \(stage.rawValue)"); fflush(stdout)
                    }
                    try vm.prepareForProduction(context: context)
                    guard try await vm.missingOfflineModels().isEmpty else {
                        throw OfflineError.unavailable("Download the required models in meeting setup first.")
                    }
                    print("MEETMIND_PIPELINE running"); fflush(stdout)
                    try await vm.startPipeline()
                    let analysis = meeting.offlineAnalysis
                    let transcript = meeting.transcriptSegments.map(\.text).joined(separator: " ").lowercased()
                    let hasExpectedWords = transcript.contains("send") && transcript.contains("estimate") && transcript.contains("tomorrow")
                    print("MEETMIND_PIPELINE result transcript=\(meeting.transcriptSegments.count) decoded=\(analysis != nil) generated_tasks=\(analysis?.analysis.flatMap(\.tasks).count ?? 0) pending=\(meeting.pendingTaskSuggestions.count) active=\(meeting.actionItems.count) expected_words=\(hasExpectedWords)")
                    fflush(stdout)
                    // The clip is the public synthetic fixture, never user content,
                    // so its derived text may be printed to diagnose a failed check.
                    let reducedResults = analysis?.analysis ?? []
                    for (index, task) in reducedResults.flatMap(\.tasks).enumerated() {
                        print("MEETMIND_PIPELINE task index=\(index) title=\(String(reflecting: task.title)) owner=\(task.owner ?? "nil") deadline=\(task.deadlineText ?? "nil") evidence=\(task.evidence.count)")
                    }
                    for (index, suggestion) in meeting.pendingTaskSuggestions.enumerated() {
                        print("MEETMIND_PIPELINE pending index=\(index) title=\(String(reflecting: suggestion.task.title)) owner=\(suggestion.task.owner ?? "nil") deadline=\(suggestion.task.deadlineText ?? "nil")")
                    }
                    print("MEETMIND_PIPELINE minutes decisions=\(reducedResults.flatMap(\.decisions).count) open_issues=\(reducedResults.flatMap(\.openIssues).count) discussion=\(reducedResults.flatMap(\.discussion).count)")
                    for (index, issue) in reducedResults.flatMap(\.openIssues).enumerated() {
                        print("MEETMIND_PIPELINE open_issue index=\(index) text=\(String(reflecting: issue.text))")
                    }
                    for (index, decision) in reducedResults.flatMap(\.decisions).enumerated() {
                        print("MEETMIND_PIPELINE decision index=\(index) text=\(String(reflecting: decision.text))")
                    }
                    print("MEETMIND_PIPELINE transcript_text=\(String(reflecting: String(transcript.prefix(400))))")
                    fflush(stdout)
                    let suggestions = meeting.pendingTaskSuggestions
                    guard vm.pipelineStatus == .completed, !meeting.transcriptSegments.isEmpty,
                          meeting.summary != nil, meeting.actionItems.isEmpty, hasExpectedWords,
                          suggestions.count == 1, let suggestion = suggestions.first,
                          suggestion.task.owner == "Rahul",
                          suggestion.task.deadlineText?.lowercased() == "tomorrow",
                          !suggestion.task.evidence.isEmpty else {
                        throw OfflineError.unavailable("Synthetic processing did not produce the expected grounded transcript, minutes, and explicit action.")
                    }
                    for _ in 0..<2 {
                        try meeting.reviewTask(suggestion, title: suggestion.task.title,
                            owner: suggestion.task.owner ?? "", category: suggestion.task.category,
                            priority: suggestion.task.priority ?? "", dueDate: nil, accept: true, context: context)
                    }
                    let freshContext = ModelContext(container)
                    let saved = try freshContext.fetch(FetchDescriptor<Meeting>()).first
                    print("MEETMIND_PIPELINE review saved_tasks=\(saved?.actionItems.count ?? 0)")
                    fflush(stdout)
                    guard saved?.actionItems.count == 1,
                          saved?.actionItems.first?.sourceEvidence?.isEmpty == false else {
                        throw OfflineError.unavailable("Synthetic task review persistence check failed.")
                    }
                    status = "Completed: transcription, speakers, grounded minutes, task review, and saved-task reload."
                    print("MEETMIND_PIPELINE completed transcript=\(meeting.transcriptSegments.count) accepted=1 duplicate=0")
                    fflush(stdout)
                } catch is CancellationError {
                    status = "Paused. Restart the synthetic check while MeetMind stays open."
                    print("MEETMIND_PIPELINE cancelled"); fflush(stdout)
                } catch {
                    status = error.localizedDescription
                    if case OfflineError.memoryBudget(let required, let available) = error {
                        print("MEETMIND_PIPELINE failed memory_required=\(required) memory_available=\(available)")
                    } else {
                        print("MEETMIND_PIPELINE failed type=\(String(reflecting: type(of: error)))")
                    }
                    fflush(stdout)
                }
                try? await MeetingAnalysisPipeline.shared.removeCheckpoint(meetingID: id)
            }
        }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { operation?.cancel() }
        }
    }
}

@MainActor
private struct ProcessingPeopleRow: View {
    let meeting: Meeting
    let openVoices: () -> Void

    private var voiceRows: [MeetingVoiceRow] {
        MeetingPeopleEditor.voices(in: meeting, record: MeetingRecordStore.shared.record(for: meeting.id))
    }
    private var voices: [Speaker] { meeting.participants.filter { $0.isUnnamedVoice } }
    private var attendees: [Speaker] { meeting.namedAttendees }

    var body: some View {
        Button(action: openVoices) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("People").foregroundStyle(.primary)
                    Text("\(attendees.count) attendees · \(voiceRows.count) detected voices")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: -6) {
                    ForEach(Array((attendees + voices).prefix(4)), id: \.id) { voice in
                        Text(voice.initials).font(.caption2.bold()).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Color(hex: voice.avatarColorHex), in: Circle())
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("People and detected voices")
    }
}

struct MeetingSeriesMenu: View {
    let meeting: Meeting
    let onError: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @State private var showsNewSeries = false
    @State private var seriesName = ""

    var body: some View {
        Menu {
            ForEach(Set(meetings.compactMap(\.seriesID)).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                if let name = meetings.first(where: { $0.seriesID == id })?.seriesName {
                    Button(name) { saveSeries(id: id, name: name) }
                }
            }
            Button("None") { saveSeries(id: nil, name: nil) }
            Button("New Series…", systemImage: "plus") {
                seriesName = ""
                showsNewSeries = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(meeting.seriesName ?? "Add to Series")
                Image(systemName: "chevron.down").font(.caption)
            }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .alert("New Series", isPresented: $showsNewSeries) {
            TextField("Series name", text: $seriesName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = seriesName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { saveSeries(id: UUID(), name: name) }
            }
        }
    }

    private func saveSeries(id: UUID?, name: String?) {
        let previous = (meeting.seriesID, meeting.seriesName)
        meeting.seriesID = id
        meeting.seriesName = name
        do { try modelContext.save() }
        catch {
            meeting.seriesID = previous.0
            meeting.seriesName = previous.1
            onError(error.localizedDescription)
        }
    }
}
