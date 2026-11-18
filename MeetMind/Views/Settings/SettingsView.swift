import SwiftUI
import SwiftData
import OfflineEngineKit

/// Main Settings configuration console for MeetMind application
public struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    
    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
    }
    
    public init() {}
    
    public var body: some View {
        Form {
            SettingsAudioQualitySection(viewModel: viewModel)
            SettingsSpeechAndAISection(viewModel: viewModel)
            Section("On-device intelligence") {
                NavigationLink("Offline analysis models") { OfflineAnalysisModelsView() }
                DisclosureGroup("Diagnostics") {
                    NavigationLink("Offline model benchmarks") { OfflineBenchmarkView() }
                }
            }
            SettingsStorageAndCacheSection(viewModel: viewModel)
            SettingsThemeAndAppearanceSection(viewModel: viewModel)
            SettingsAboutAndDiagnosticsSection(viewModel: viewModel)
        }
        .navigationTitle("Settings")
        .background(Theme.Colors.background)
    }
}

@MainActor
struct OfflineAnalysisModelsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var profiles: [ModelProfile] = []
    @State private var installed = Set<String>()
    @State private var operation: Task<Void, Never>?
    @State private var busy = false
    @State private var progress = 0.0
    @State private var message = ""

    var body: some View {
        List {
            Section {
                Text("Meeting audio, transcripts, and analysis stay on this iPhone. Internet is needed only to download public model files. Keep the app open during downloads and meeting analysis.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Hindi–English accuracy is still being evaluated. Review generated tasks and source quotes before accepting them.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message) }
                if busy {
                    ProgressView(value: progress)
                    Button("Pause download") { operation?.cancel() }
                }
            }
            ForEach(profiles) { profile in
                Section(profile.name) {
                    LabeledContent("Download size", value: ByteCountFormatter.string(fromByteCount: profile.downloadBytes, countStyle: .file))
                    LabeledContent("Status", value: installed.contains(profile.id) ? "Downloaded" : "Not downloaded")
                    Button(installed.contains(profile.id) ? "Verify or repair model" : "Download model") {
                        perform {
                            try await OfflineModelStore.shared.install(profile) { value in
                                Task { @MainActor in progress = value }
                            }
                            message = "Model verified and ready."
                        }
                    }.disabled(busy)
                    if installed.contains(profile.id) {
                        Button("Remove model download", role: .destructive) {
                            perform {
                                try await OfflineModelStore.shared.remove(profile)
                                message = "Model removed. Saved recordings and results are preserved. Download it again before analyzing another meeting."
                            }
                        }.disabled(busy)
                    }
                }
            }
            NavigationLink("Model licenses") {
                ScrollView { Text(OfflineModelStore.notices).font(.footnote).textSelection(.enabled).padding() }
                    .navigationTitle("Licenses")
            }
        }
        .navigationTitle("Offline models")
        .task {
            do {
                profiles = try OfflineModelStore.profiles().filter { MeetingAnalysisPipeline.requiredModelIDs.contains($0.id) }
                await refresh()
            } catch { message = error.localizedDescription }
        }
        .onDisappear { operation?.cancel(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { operation?.cancel() } }
    }

    private func refresh() async {
        var ready = Set<String>()
        for profile in profiles {
            if await OfflineModelStore.shared.isInstalled(profile) { ready.insert(profile.id) }
        }
        installed = ready
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        progress = 0
        message = ""
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task { @MainActor in
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await action() }
            catch is CancellationError { message = "Paused. Completed download chunks are saved; tap Download to resume." }
            catch { message = error.localizedDescription }
            await refresh()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsViewModel())
            .modelContainer(for: Meeting.self, inMemory: true)
    }
}
