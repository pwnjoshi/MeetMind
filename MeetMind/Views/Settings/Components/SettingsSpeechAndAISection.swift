import SwiftUI

/// Speech recognition locale and on-device AI settings section
public struct SettingsSpeechAndAISection: View {
    @Bindable public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("Speech Recognition & AI Intelligence")) {
            Picker("Speech Language", selection: Binding(
                get: { viewModel.speechLanguageLocale },
                set: { viewModel.setSpeechLanguageLocale($0) }
            )) {
                ForEach(viewModel.availableLanguages) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            
            Toggle("On-Device Recognition Only", isOn: $viewModel.isOnDeviceRecognitionOnly)
                .tint(Theme.Colors.primarySlate)
                .disabled(viewModel.isOnlineRecognitionDisabled)
            
            if viewModel.mustUseOnDeviceRecognition {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(Theme.Colors.warmAmber)
                    Text("Offline mode: Neural speech engine active")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            Picker("Summary Style", selection: $viewModel.summaryStyle) {
                Text("Executive Brief").tag(SummaryStyle.executive)
                Text("Detailed Analysis").tag(SummaryStyle.detailed)
            }
            
            HStack {
                Text("Custom AI API Key")
                Spacer()
                Text(viewModel.maskedAPIKey)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .font(Typography.timecode)
            }
        }
    }
}
