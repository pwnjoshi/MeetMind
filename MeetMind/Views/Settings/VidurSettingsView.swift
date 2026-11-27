import SwiftUI
import OfflineEngineKit

/// Vidur settings (Figma 1887:826 with Model, Answer Length, Search Across menus and
/// the Clear Vidur History alert).
@MainActor
public struct VidurSettingsView: View {
    @Environment(SettingsViewModel.self) private var environmentViewModel: SettingsViewModel?
    @State private var localViewModel = SettingsViewModel()
    @AppStorage(VidurDeepAnswerSetting.key) private var deepAnswers = true
    @State private var showingClearAlert = false

    private let preferences = VidurPreferences.shared

    public init() {}

    private var viewModel: SettingsViewModel {
        environmentViewModel ?? localViewModel
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
                Text("Deep answers find the matching minutes, transcript passages and notes, then write a short reply in your own words and language. Facts the minutes state outright show at once, and are reworded when the model is already loaded. Turn off for instant matches only. Sources link each answer to the minutes or the moment in the recording.")
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
        .alert("Clear Vidur History?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { preferences.clearHistory() }
        } message: {
            Text("All saved Vidur questions and answers on this iPhone will be deleted. Your meetings and minutes are not affected.")
        }
    }
}
