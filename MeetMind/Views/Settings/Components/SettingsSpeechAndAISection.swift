import SwiftUI

/// Speech recognition locale and on-device AI settings section
public struct SettingsSpeechAndAISection: View {
    @Bindable public var viewModel: SettingsViewModel
    
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Section(header: Text("Speech Recognition & AI Intelligence")) {
            Picker("Saved recording language", selection: Binding(
                get: { viewModel.savedRecordingLanguage },
                set: { viewModel.setSavedRecordingLanguage($0) }
            )) {
                ForEach(SavedRecordingLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Text("Use Hindi + English for Hinglish meetings. This prevents automatic detection from selecting Urdu and is used for the final on-device transcript.")
                .font(.footnote).foregroundStyle(.secondary)

            Picker("Live preview language", selection: Binding(
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
            
            Text("The live preview is provisional. When recording ends, MeetMind replaces it with the selected-language offline transcript before generating minutes and tasks.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
