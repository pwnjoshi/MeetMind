import SwiftUI
import SwiftData

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
                NavigationLink("Offline model benchmarks") { OfflineBenchmarkView() }
            }
            SettingsStorageAndCacheSection(viewModel: viewModel)
            SettingsThemeAndAppearanceSection(viewModel: viewModel)
            SettingsAboutAndDiagnosticsSection(viewModel: viewModel)
        }
        .navigationTitle("Settings")
        .background(Theme.Colors.background)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(SettingsViewModel())
            .modelContainer(for: Meeting.self, inMemory: true)
    }
}
