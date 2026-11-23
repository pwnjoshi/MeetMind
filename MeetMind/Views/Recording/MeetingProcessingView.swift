import SwiftUI
import SwiftData
import OfflineEngineKit
import Darwin
import UserNotifications

private enum ProcessingStageState {
    case done
    case working
    case waiting
}

private struct ProcessingStageRow: Identifiable {
    let title: String
    let first: Int
    let last: Int
    var id: Int { first }
}

/// Remembers which meetings were just finished from the live recording page, so the
/// processing screen starts the run by itself instead of asking for "Process Now".
/// A request is single-use and expires, so reopening a meeting later never auto-starts.
@MainActor
final class ProcessingAutoStart {
    static let shared = ProcessingAutoStart()
    private var requests: [UUID: Date] = [:]
    private init() {}

    func request(meetingID: UUID) {
        requests[meetingID] = Date()
    }

    /// Returns true once for a recent request, then forgets it.
    func consume(meetingID: UUID) -> Bool {
        guard let requestedAt = requests.removeValue(forKey: meetingID) else { return false }
        return Date().timeIntervalSince(requestedAt) < 300
    }
}

/// Post-recording screen (Figma B4 "Writing minutes"). It shows honest progress while the on-device
/// minutes are written and offers the next steps. When the minutes exist it opens the B6 document.
public struct MeetingProcessingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsViewModel.self) private var settings
    @State private var showsVidur = false
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meetings: [Meeting]
    @State private var showsNameSpeakers = false
    @State private var showsPeople = false
    @State private var showsRename = false
    @State private var meetingTitleDraft = ""
    @State private var preparingSpeakers = false
    @State private var showsMinutes = false
    @State private var showsTranscript = false
    @State private var processingError: String?
    @State private var viewModel: ProcessingPipelineViewModel
    @State private var missingModels: [ModelProfile] = []
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var downloadProgress: Double = 0
    @State private var downloading = false
    @State private var checkingModels = false
    /// True from arrival after a finished recording until the automatic start has been decided.
    @State private var autoStartInFlight = false
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
            VStack(alignment: .leading, spacing: 20) {
                header
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    VStack(alignment: .leading, spacing: 20) {
                        statusCard
                        if busy || OfflineAnalysisBackgroundScheduler.status(for: meetingId) != nil {
                            progressSection
                        }
                        nextSection
                    }
                }
                if let processingError {
                    Text(processingError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if meeting != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Vidur", systemImage: "sparkles") {
                        showsVidur = true
                    }.labelStyle(.iconOnly)
                }
            }
        }
        .tint(Theme.Colors.manentAccent)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationDestination(isPresented: $showsVidur) {
            RootAskAISheet(meetingId: meetingId, modelContext: modelContext) { showsVidur = false }
        }
        .navigationDestination(isPresented: $showsMinutes) {
            if let meeting {
                MeetingDetailView(
                    viewModel: MeetingDetailViewModel(meeting: meeting, meetingId: meetingId, modelContext: modelContext)
                )
            }
        }
        .navigationDestination(isPresented: $showsTranscript) {
            MeetingTranscriptScreen(meetingId: meetingId)
        }
        .sheet(isPresented: $showsNameSpeakers) {
            if let meeting {
                NameSpeakersView(meeting: meeting)
                    .presentationDragIndicator(.visible)
            }
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
            // model download or meeting analysis without an explicit tap. A run that
            // is already processing this meeting owns its job record; leave it alone.
            // Arriving from a finished recording starts processing once, below. The request
            // is consumed here so a later reopen of this screen never starts a run.
            let wantsAutoStart = ProcessingAutoStart.shared.consume(meetingID: meetingId)
            guard !OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId) else { return }
            checkingModels = true
            autoStartInFlight = wantsAutoStart
            Task { @MainActor in
                defer {
                    checkingModels = false
                    autoStartInFlight = false
                }
                do {
                    try viewModel.prepareForProduction(context: modelContext, settings: settings)
                    _ = try await viewModel.refreshAnalysisState()
                    processingError = viewModel.jobSnapshot?.failure?.message
                    if wantsAutoStart { startAutomaticallyIfEligible() }
                } catch {
                    processingError = (error as? AnalysisCoordinatorError)?.errorDescription
                        ?? (error as? AnalysisJobStoreError)?.errorDescription
                        ?? AnalysisFailure.stable(.processingFailed).message
                }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var meeting: Meeting? { meetings.first { $0.id == meetingId } }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                meetingTitleDraft = meeting?.title ?? ""
                showsRename = true
            } label: {
                Text(meeting?.title ?? "Quick meeting")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .disabled(meeting == nil)
            .accessibilityHint("Rename this meeting")
            if let meeting {
                Text(subtitle(for: meeting))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    MeetingSeriesMenu(meeting: meeting) { processingError = $0 }
                    peoplePill
                }
                .padding(.top, 2)
            }
        }
    }

    /// Opens the people editor. People is edited here, so it is not repeated in a menu.
    private var peoplePill: some View {
        Button { showsPeople = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2").font(.caption)
                Text("People")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .accessibilityHint("Edit who was in this meeting")
    }

    private func subtitle(for meeting: Meeting) -> String {
        var parts = [meeting.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if meeting.duration >= 30 {
            parts.append("\(max(1, Int((meeting.duration / 60).rounded()))) min")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Status card

    private var isRunning: Bool {
        busy || OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId)
    }

    private func panel<Content: View>(highlight: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                if highlight {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Theme.Colors.manentAccent.opacity(0.16), Color.blue.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
    }

    private var runningProgress: Double {
        if downloading { return max(0, min(1, downloadProgress)) }
        if busy { return max(0, min(1, viewModel.overallProgress)) }
        return Double(max(activeStep, 0)) / 5.0
    }

    private var runningTitle: String {
        if downloading { return "Downloading models\u{2026}" }
        switch activeStep {
        case ..<1: return preparingSpeakers ? "Preparing speaker review\u{2026}" : "Getting ready\u{2026}"
        case 1: return "Writing the transcript\u{2026}"
        case 2: return "Finding speakers\u{2026}"
        default: return "Writing minutes\u{2026}"
        }
    }

    private func progressRing(_ value: Double) -> some View {
        ZStack {
            Circle().stroke(Theme.Colors.manentAccent.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.05, min(1, value)))
                .stroke(Theme.Colors.manentAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusCard: some View {
        if checkingModels {
            panel {
                Text("Verifying on-device models").font(.title3.bold())
                ProgressView()
                Text("Checking each required model before processing starts.").foregroundStyle(.secondary)
            }
        } else if busy {
            panel(highlight: true) {
                runningHeader(detail: "Audio and text stay on this iPhone.")
                if preparingSpeakers {
                    Button("Pause speaker review", systemImage: "pause.fill") { operation?.cancel() }
                } else {
                    HStack {
                        Button("Keep in Background", systemImage: "clock") { queueAnalysis() }
                        Spacer()
                        Button("Pause", systemImage: "pause.fill") { operation?.cancel() }
                    }
                }
            }
        } else if let backgroundStatus = OfflineAnalysisBackgroundScheduler.status(for: meetingId) {
            panel(highlight: true) {
                runningHeader(detail: backgroundStatus)
                if ContinuedAnalysisRun.shared.isRunning(meetingID: meetingId) {
                    Button("Pause", systemImage: "pause.fill") {
                        ContinuedAnalysisRun.shared.cancel(meetingID: meetingId)
                    }
                }
            }
        } else if viewModel.jobSnapshot?.state == .queued {
            panel {
                Text(autoStartInFlight ? "Starting\u{2026}" : "Queued").font(.title3.bold())
                Text("Your recording is saved and ready for on-device processing.")
                    .foregroundStyle(.secondary)
            }
        } else if modelsRequired {
            panel {
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
            }
        } else if viewModel.jobSnapshot?.state == .paused {
            panel {
                Text("Processing paused").font(.title3.bold())
                Text("Your recording and completed steps are saved.").foregroundStyle(.secondary)
                Button("Retry") { start() }
                    .buttonStyle(.borderedProminent)
            }
        } else if let failure = viewModel.jobSnapshot?.failure {
            panel {
                Text("Processing needs attention").font(.title3.bold())
                Text(failure.message).foregroundStyle(.secondary)
                recoveryButton(for: failure)
            }
        } else if viewModel.jobSnapshot?.state == .speakerReview || meeting?.analysisState == "speakerReview" {
            panel {
                Text("Who said what?").font(.title3.bold())
                Text(viewModel.jobSnapshot?.warning ?? "Assign detected voices, or continue with unnamed speakers.")
                    .foregroundStyle(.secondary)
                Button("Name the Voices") { showsNameSpeakers = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if isReadyForReview {
            panel(highlight: true) {
                Text("Minutes are ready").font(.title3.bold())
                Text("Review the draft before you share it.").foregroundStyle(.secondary)
                Button("Open Minutes") { showsMinutes = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            panel {
                if meeting?.analysisState == "failed" || meeting?.analysisState == "paused" {
                    Text(meeting?.analysisState == "failed" ? "Processing needs attention" : "Processing paused")
                        .font(.title3.bold())
                    Text(processingError ?? "Your audio is saved. You can continue from the last completed step.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Recording saved").font(.title3.bold())
                    Text("Your audio is saved on this iPhone. Generate minutes when you are ready.")
                        .foregroundStyle(.secondary)
                }
                if meeting?.analysisState != "speakerReview" && meeting?.analysisState != "completed" {
                    Button("Detect Voices", systemImage: "waveform") {
                        start(download: true, speakersOnly: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func runningHeader(detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            progressRing(runningProgress)
            VStack(alignment: .leading, spacing: 4) {
                Text(runningTitle).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        ProgressView(value: runningProgress)
            .tint(Theme.Colors.manentAccent)
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((runningProgress * 100).rounded())) percent")
        Text("You can close the app. We\u{2019}ll notify you when it\u{2019}s ready.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: Progress

    private var voiceRows: [MeetingVoiceRow] {
        guard let meeting else { return [] }
        return MeetingPeopleEditor.voices(in: meeting, record: MeetingRecordStore.shared.record(for: meeting.id))
    }

    private var stageRows: [ProcessingStageRow] {
        var rows = [
            ProcessingStageRow(title: "Transcript", first: 1, last: 1),
            ProcessingStageRow(title: "Speakers found", first: 2, last: 2)
        ]
        if !preparingSpeakers {
            rows.append(ProcessingStageRow(title: "Minutes, decisions, actions", first: 3, last: 4))
        }
        return rows
    }

    private func stageState(_ row: ProcessingStageRow) -> ProcessingStageState {
        if activeStep > row.last { return .done }
        if isRunning && activeStep >= row.first { return .working }
        return .waiting
    }

    private func stageDetail(_ row: ProcessingStageRow, state: ProcessingStageState) -> String {
        switch state {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done:
            if row.first == 2 {
                let count = voiceRows.count
                return count > 0 ? (count == 1 ? "1 voice" : "\(count) voices") : "Done"
            }
            return "Done"
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress").font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Recording saved").font(.body)
                    Spacer(minLength: 8)
                    if let meeting, meeting.duration >= 30 {
                        Text("\(max(1, Int((meeting.duration / 60).rounded()))) min")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                ForEach(stageRows) { row in
                    Divider()
                    let state = stageState(row)
                    HStack(spacing: 12) {
                        Image(systemName: state == .done ? "checkmark.circle.fill" : (state == .working ? "circle.dotted" : "circle"))
                            .foregroundStyle(state == .done ? Color.green : (state == .working ? Theme.Colors.manentAccent : Color.secondary))
                        Text(row.title).font(.body)
                        Spacer(minLength: 8)
                        Text(stageDetail(row, state: state))
                            .font(.subheadline)
                            .foregroundStyle(state == .working ? Theme.Colors.manentAccent : Color.secondary)
                    }
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Next

    @ViewBuilder
    private var nextSection: some View {
        let rows = voiceRows
        let unnamed = rows.filter { $0.assignedPersonID == nil }.count
        let canNameVoices = unnamed > 0 && (activeStep >= 3 || isReadyForReview)
        let showsTranscriptRow = meeting?.resolvedAudioFileURL != nil || !(meeting?.transcriptSegments.isEmpty ?? true)
        if canNameVoices || showsTranscriptRow {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next").font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    if canNameVoices {
                        nextRow(
                            icon: "person.2.fill",
                            title: unnamed == 1 ? "Name the voice" : "Name the \(unnamed) voices",
                            detail: "So minutes show who decided what",
                            tint: Theme.Colors.manentAccent
                        ) { showsNameSpeakers = true }
                    }
                    if canNameVoices && showsTranscriptRow { Divider().padding(.leading, 56) }
                    if showsTranscriptRow {
                        nextRow(
                            icon: "doc.text",
                            title: "Transcript and audio",
                            detail: "Read and play the recording",
                            tint: Color.primary
                        ) { showsTranscript = true }
                        .disabled(busy)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func nextRow(icon: String, title: String, detail: String, tint: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(tint)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let backgroundRunning = OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId)
            let queued = OfflineAnalysisBackgroundScheduler.status(for: meetingId) != nil
                || viewModel.jobSnapshot?.state == .queued
            if !busy && !backgroundRunning && !autoStartInFlight {
                Button {
                    if isReadyForReview { showsMinutes = true }
                    else { start(download: modelsRequired) }
                } label: {
                    Text(isReadyForReview ? "Open Minutes" :
                         (modelsRequired ? "Download & Continue" :
                          (queued ? "Resume Processing" : "Generate Minutes")))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.manentAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(checkingModels)
                .padding()
            }
        }
    }

    // MARK: State

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

    /// Processing continues after this screen closes (and, on iOS 26, after the app
    /// is backgrounded). Only the notification permission is requested here, so the
    /// person hears when the minutes are ready.
    private func queueAnalysis() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            dismiss()
        }
    }

    /// Starts the run once after a finished recording. It never downloads models: when
    /// models are missing the "Models Required" card keeps the explicit download button.
    private func startAutomaticallyIfEligible() {
        guard !busy, !isRunning, !isReadyForReview, !modelsRequired,
              !ContinuedAnalysisRun.shared.hasActiveRun else { return }
        let job = viewModel.jobSnapshot?.state
        guard viewModel.jobSnapshot?.failure == nil,
              job == nil || job == .queued || job == .verifying else { return }
        let state = meeting?.analysisState
        guard state == nil || state == "ready" else { return }
        start()
    }

    private func start(download: Bool = false, speakersOnly: Bool = false) {
        guard !busy else { return }
        guard !OfflineAnalysisBackgroundScheduler.isRunning(meetingID: meetingId) else {
            processingError = "This meeting is already processing. Follow its progress above."
            return
        }
        guard !ContinuedAnalysisRun.shared.hasActiveRun else {
            processingError = "Another meeting is processing. This one can start when it finishes."
            return
        }
        OfflineAnalysisBackgroundScheduler.remove(meetingID: meetingId)
        busy = true
        preparingSpeakers = speakersOnly
        processingError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        let id = meetingId
        viewModel.onOfflineStageChanged = { stage in
            ContinuedAnalysisRun.shared.report(stage, meetingID: id)
        }
        // The run belongs to the app, not this screen: leaving the screen or the app
        // does not stop it. Pause, or Stop in the iOS Live Activity, does.
        let work: @MainActor () async -> Bool = {
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
                    guard download else { return false }
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
                    showsNameSpeakers = true
                } else {
                    try await viewModel.startPipeline()
                }
                return true
            } catch is CancellationError {
                processingError = "Paused. Your audio, completed steps, and partial model downloads are saved. Tap Resume when you return."
            } catch {
                processingError = viewModel.jobSnapshot?.failure?.message
                    ?? (error as? AnalysisCoordinatorError)?.errorDescription
                    ?? (error as? AnalysisJobStoreError)?.errorDescription
                    ?? AnalysisFailure.stable(.processingFailed).message
            }
            return false
        }
        guard let task = ContinuedAnalysisRun.shared.start(meetingID: id, title: meeting?.title ?? "Meeting minutes",
                                                          work: work) else {
            busy = false
            preparingSpeakers = false
            UIApplication.shared.isIdleTimerDisabled = false
            processingError = "Another meeting is processing. This one can start when it finishes."
            return
        }
        operation = task
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
