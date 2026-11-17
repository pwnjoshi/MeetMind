import SwiftUI
import SwiftData

/// Dynamic root switcher between Onboarding flow and Main Tab navigation
public struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settingsVM
    
    public init() {}
    
    public var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingContainerView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: appState.hasCompletedOnboarding)
        .sheet(item: Bindable(appState).activeSheet) { sheetDestination(for: $0) }
        .modifier(RootAlertModifier(appState: appState))
        .preferredColorScheme(settingsVM.preferredColorScheme?.systemColorScheme)
    }
    
    @ViewBuilder
    private func sheetDestination(for sheet: AppSheet) -> some View {
        switch sheet {
        case .newMeeting:
            NewMeetingSheet(modelContext: modelContext) { meeting in
                appState.activeSheet = nil
                if meeting.status == .recording {
                    router.navigate(to: .liveRecording(id: meeting.id), in: .home)
                }
            }
            .environment(\.modelContext, modelContext)
        case .scheduleMeeting:
            ScheduleMeetingView(viewModel: MeetingSetupViewModel(modelContext: modelContext)) { _ in
                appState.activeSheet = nil
            }
            .environment(\.modelContext, modelContext)
        case .audioImport:
            AudioImportView(viewModel: MeetingSetupViewModel(modelContext: modelContext)) { meeting in
                appState.activeSheet = nil
                router.navigate(to: .meetingProcessing(id: meeting.id), in: .home)
            }
            .environment(\.modelContext, modelContext)
        case .editActionItem(let id):
            RootEditActionItemSheet(actionItemId: id, modelContext: modelContext) {
                appState.activeSheet = nil
            }
        case .exportMinutes(let id):
            RootExportMinutesSheet(meetingId: id, modelContext: modelContext) {
                appState.activeSheet = nil
            }
        case .askAIAssistant(let id):
            RootAskAISheet(meetingId: id, modelContext: modelContext) {
                appState.activeSheet = nil
            }
        }
    }
}
