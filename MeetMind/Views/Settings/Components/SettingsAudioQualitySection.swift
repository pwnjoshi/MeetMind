import SwiftUI

/// Audio quality and background recording configuration section
public struct SettingsAudioQualitySection: View {
    @Bindable public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("Audio Quality & Recording")) {
            Picker("Encoding Quality", selection: Binding(
                get: { viewModel.audioQuality },
                set: { viewModel.setAudioQuality($0) }
            )) {
                Text("High Fidelity (128 kbps)").tag(AudioQuality.high)
                Text("Standard (64 kbps)").tag(AudioQuality.standard)
            }
            .disabled(viewModel.isAudioSettingsLocked)
            
            HStack {
                Text("Storage Rate")
                Spacer()
                Text(viewModel.audioQuality.storageEstimatePerHour)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .font(Typography.caption)
            }
            
            Toggle("Background Noise Suppression", isOn: $viewModel.isNoiseSuppressionEnabled)
                .tint(Theme.Colors.primarySlate)
                .disabled(viewModel.isAudioSettingsLocked)
            
            if viewModel.isAudioSettingsLocked {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Theme.Colors.warmAmber)
                    Text("Audio settings locked during active recording")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}
