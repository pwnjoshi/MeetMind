import SwiftUI

/// Theme and appearance mode settings section
public struct SettingsThemeAndAppearanceSection: View {
    @Bindable public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("Theme & Appearance")) {
            Picker("Appearance", selection: Binding(
                get: { viewModel.themeMode },
                set: { viewModel.setThemeMode($0) }
            )) {
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
            
            Toggle("High Contrast Mode", isOn: $viewModel.isHighContrastEnabled)
                .tint(Theme.Colors.primarySlate)
            
            HStack(spacing: Spacing.sm) {
                Text("Active Swatches")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Circle().fill(Theme.Colors.primarySlate).frame(width: 16, height: 16)
                Circle().fill(Theme.Colors.warmAmber).frame(width: 16, height: 16)
                Circle().fill(Theme.Colors.liveBlue).frame(width: 16, height: 16)
                Circle().fill(Theme.Colors.aiPurple).frame(width: 16, height: 16)
                Circle().fill(Theme.Colors.mintGreen).frame(width: 16, height: 16)
            }
        }
    }
}
