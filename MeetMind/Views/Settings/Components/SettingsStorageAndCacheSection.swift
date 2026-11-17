import SwiftUI

/// Local storage meter and cache management section
public struct SettingsStorageAndCacheSection: View {
    @Bindable public var viewModel: SettingsViewModel
    @State private var showingClearCacheAlert = false
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("Storage & Cache Management")) {
            HStack {
                Text("Temporary Cache")
                Spacer()
                Text(viewModel.formattedStorageUsage)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Button(role: .destructive) {
                showingClearCacheAlert = true
            } label: {
                Text("Clear Temporary Cache")
            }
            .alert("Clear Temporary Cache?", isPresented: $showingClearCacheAlert) {
                Button("Clear", role: .destructive) {
                    viewModel.clearTemporaryCache()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears transient audio waveforms and cache without deleting saved meeting recordings or transcripts.")
            }
            
            Toggle("iCloud Sync", isOn: $viewModel.isiCloudSyncEnabled)
                .tint(Theme.Colors.primarySlate)
        }
    }
}
