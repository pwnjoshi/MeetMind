import SwiftUI
import SwiftData
import OfflineEngineKit
import Darwin

/// Foreground-only offline analysis with explicit model setup and safe retry.
public struct MeetingProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var processingError: String?
    @State private var viewModel: ProcessingPipelineViewModel
    @State private var missingModels: [ModelProfile] = []
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var downloadProgress: Double = 0
    @State private var downloading = false
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
            VStack(spacing: 24) {
                Text(missingModels.isEmpty ? "Analyze meeting" : "Set up offline analysis")
                    .font(.title2.bold())
                Text("Audio and meeting content stay on this iPhone. Keep MeetMind open during analysis. Suggested tasks need your review before saving.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !missingModels.isEmpty {
                    ForEach(missingModels) { profile in
                        LabeledContent(profile.name, value: ByteCountFormatter.string(fromByteCount: profile.downloadBytes, countStyle: .file))
                    }
                    Text("One-time public model downloads require internet and free storage. Recognition and analysis then run offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Download models and analyze") { start(download: true) }
                        .buttonStyle(.borderedProminent).disabled(busy)
                }
                if downloading {
                    ProgressView("Downloading models", value: downloadProgress)
                } else {
                    ProcessingProgressRingView(progress: viewModel.overallProgress)
                    ForEach(viewModel.stages) { stage in
                        ProcessingStageRowView(stage: stage) { start() }
                    }
                }
                if let processingError {
                    Text(processingError).foregroundStyle(.secondary)
                    if !busy && missingModels.isEmpty {
                        Button("Resume analysis") { start() }.buttonStyle(.borderedProminent)
                    }
                }
                if busy {
                    Button("Pause analysis", role: .cancel) { operation?.cancel() }
                }
                Button("Back to meeting") { operation?.cancel(); dismiss() }
            }.padding(24)
        }
        .background(Theme.Colors.background)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.onNavigateToDetail = { id in
                router.navigate(to: .meetingDetail(id: id), in: .home)
            }
            if operation == nil { start() }
        }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { operation?.cancel() }
        }
    }

    private func start(download: Bool = false) {
        guard !busy else { return }
        busy = true
        processingError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer {
                busy = false
                downloading = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                try viewModel.prepareForProduction(context: modelContext, settings: settings)
                missingModels = try await viewModel.missingOfflineModels()
                if !missingModels.isEmpty {
                    guard download else { return }
                    downloading = true
                    for profile in missingModels {
                        downloadProgress = 0
                        try await OfflineModelStore.shared.install(profile) { value in
                            Task { @MainActor in downloadProgress = value }
                        }
                    }
                    missingModels = try await viewModel.missingOfflineModels()
                    downloading = false
                }
                try Task.checkCancellation()
                try await viewModel.startPipeline()
            } catch is CancellationError {
                processingError = "Paused. Your audio, completed steps, and partial model downloads are saved. Tap Resume when you return."
            } catch {
                processingError = error.localizedDescription
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
                    guard vm.pipelineStatus == .completed, !meeting.transcriptSegments.isEmpty,
                          meeting.summary != nil, meeting.actionItems.isEmpty,
                          let suggestion = meeting.pendingTaskSuggestions.first else {
                        throw OfflineError.unavailable("Synthetic processing did not produce a reviewable task.")
                    }
                    for _ in 0..<2 {
                        try meeting.reviewTask(suggestion, title: suggestion.task.title,
                            owner: suggestion.task.owner ?? "", category: suggestion.task.category,
                            priority: suggestion.task.priority ?? "", dueDate: nil, accept: true, context: context)
                    }
                    let freshContext = ModelContext(container)
                    let saved = try freshContext.fetch(FetchDescriptor<Meeting>()).first
                    guard saved?.actionItems.count == 1,
                          saved?.actionItems.first?.sourceEvidence?.isEmpty == false else {
                        throw OfflineError.unavailable("Synthetic task review persistence check failed.")
                    }
                    status = "Completed: transcription, speakers, analysis, task review, and saved-task reload."
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
        .onChange(of: scenePhase) { _, phase in if phase != .active { operation?.cancel() } }
    }
}
