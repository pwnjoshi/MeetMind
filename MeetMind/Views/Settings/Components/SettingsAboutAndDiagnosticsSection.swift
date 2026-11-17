import SwiftUI

/// About and system diagnostics section
public struct SettingsAboutAndDiagnosticsSection: View {
    @Bindable public var viewModel: SettingsViewModel
    @State private var showingResetAlert = false
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("About & System Information")) {
            HStack {
                Text("Application")
                Spacer()
                Text("MeetMind iOS")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            HStack {
                Text("Version")
                Spacer()
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3"))")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            HStack {
                Text("Architecture")
                Spacer()
                Text("Clean Arch + SwiftData")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .font(Typography.caption)
            }
            
            Button("Reset to Factory Defaults", role: .destructive) {
                showingResetAlert = true
            }
            .alert("Reset All Preferences?", isPresented: $showingResetAlert) {
                Button("Reset Defaults", role: .destructive) {
                    viewModel.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets your audio bitrate, theme mode, and speech locale back to original factory defaults.")
            }
        }
    }
}
