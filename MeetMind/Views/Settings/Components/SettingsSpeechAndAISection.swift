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
            
            Label("Speech processing stays on this iPhone", systemImage: "iphone")
            
            if viewModel.mustUseOnDeviceRecognition {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(Theme.Colors.warmAmber)
                    Text("Cloud speech recognition is disabled")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            Picker("Summary Style", selection: $viewModel.summaryStyle) {
                Text("Executive Brief").tag(SummaryStyle.executive)
                Text("Detailed Analysis").tag(SummaryStyle.detailed)
            }
            
            Text("Summaries are generated locally from your transcript.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
