import SwiftUI
import OfflineEngineKit

/// Vidur settings (Figma 1887:826 with Model, Answer Length, Search Across menus and
/// the Clear Vidur History alert).
@MainActor
public struct VidurSettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    @AppStorage(VidurDeepAnswerSetting.key) private var deepAnswers = true
    @AppStorage(VidurVoiceSettings.voiceRepliesKey) private var voiceReplies = false
    @AppStorage(VidurVoiceSettings.heyVidurKey) private var heyVidur = false
    @State private var showingClearAlert = false
    @State private var permissionMessage: String?

    private let preferences = VidurPreferences.shared

    public init() {}

    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
    }

    /// Turning Hey Vidur on asks for microphone and speech access first. It stays off if either is refused.
    private var heyVidurBinding: Binding<Bool> {
        Binding(
            get: { heyVidur },
            set: { newValue in
                guard newValue else { heyVidur = false; return }
                Task { @MainActor in
                    let granted = await VidurPermissions.requestAll()
                    heyVidur = granted
                    if !granted {
                        permissionMessage = "Allow Microphone and Speech Recognition for Manent in Settings, then turn Hey Vidur on again."
                    }
                }
            })
    }

    public var body: some View {
        Form {
            Section {
                SettingsBanner(title: "Vidur", detail: "Runs on this iPhone. Your meetings never leave the device.",
                               systemImage: "sparkles", tint: Theme.Colors.manentAccent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Model", value: VidurModel.fast.title)
                Picker("Answer Length", selection: Binding(
                    get: { preferences.answerLength },
                    set: { preferences.answerLength = $0 }
                )) {
                    ForEach(VidurAnswerLength.allCases) { length in
                        Text(length.title).tag(length)
                    }
                }
                .pickerStyle(.menu)
                LabeledContent("Active engine", value: VidurTieredAnswerService.activeEngineName)
            } header: {
                Text("Model")
            } footer: {
                Text("Runs on this iPhone. Your meetings never leave the device. Used for new minutes and Vidur answers; download models under Offline analysis models.")
            }

            Section {
                Toggle("Deep Answers", isOn: $deepAnswers)
                Toggle("Show Sources", isOn: Binding(
                    get: { preferences.showsSources },
                    set: { preferences.showsSources = $0 }
                ))
            } header: {
                Text("Answers")
            } footer: {
                Text("Deep answers search the minutes, transcript and notes and write a direct reply in your language. They take a few seconds. Turn off for instant matches only. Sources link each answer to the minutes or the moment in the recording.")
            }

            Section {
                Toggle("Voice Replies", isOn: $voiceReplies)
                Toggle("Hey Vidur", isOn: heyVidurBinding)
            } header: {
                Text("Voice")
            } footer: {
                Text("Voice Replies lets Vidur read answers aloud. Hey Vidur is off by default. When on, Vidur listens for the phrase \u{201C}Hey Vidur\u{201D} while Manent is open on screen, then opens and listens for your request. It uses on-device speech recognition only, so nothing is recorded, stored or sent, and only the words after the phrase are used. It stops when the app goes to the background, when a recording starts, or when another app is playing audio. It needs microphone and speech access and uses some battery while listening. Vidur is never active during a recording.")
            }

            Section {
                Picker("Search Across", selection: Binding(
                    get: { preferences.searchScope },
                    set: { preferences.searchScope = $0 }
                )) {
                    ForEach(VidurSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Search")
            }

            Section {
                Button("Clear Vidur History", role: .destructive) { showingClearAlert = true }
                    .disabled(preferences.history.isEmpty)
            } footer: {
                Text("\(preferences.history.count) saved \(preferences.history.count == 1 ? "question" : "questions") on this iPhone.")
            }

            SettingsSpeechAndAISection(viewModel: viewModel)
            Section { NavigationLink("Offline analysis models") { OfflineAnalysisModelsView() } }
        }
        .navigationTitle("Vidur")
        .navigationBarTitleDisplayMode(.large)
        .tint(Theme.Colors.manentAccent)
        .alert("Hey Vidur needs access", isPresented: Binding(
            get: { permissionMessage != nil },
            set: { if !$0 { permissionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(permissionMessage ?? "")
        }
        .alert("Clear Vidur History?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { preferences.clearHistory() }
        } message: {
            Text("All saved Vidur questions and answers on this iPhone will be deleted. Your meetings and minutes are not affected.")
        }
    }
}
