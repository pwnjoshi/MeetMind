import SwiftUI
import SwiftData
import OfflineEngineKit

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
