import SwiftUI
import SwiftData

/// Dynamic root switcher between Onboarding flow and Main Tab navigation
public struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settingsVM
    @Environment(RecordingRecoveryCenter.self) private var recordingRecovery
    
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
        .overlay(alignment: .top) { recordingRecoveryBanner }
        .confirmationDialog(
            "Recording recovery",
            isPresented: Binding(
                get: { recordingRecovery.isPresentingPending },
                set: { if !$0 { recordingRecovery.dismissPendingPrompt() } }
            ),
            titleVisibility: .visible
        ) {
            if recordingRecovery.pending?.reason == .meetingMissing {
                Button("Recover as New Meeting") {
                    recordingRecovery.recoverPendingAsNew(modelContext: modelContext)
                }
            }
            Button("Delete Recording…", role: .destructive) {
                recordingRecovery.dismissPendingPrompt()
                recordingRecovery.isShowingDeleteConfirmation = true
            }
            Button("Keep for Later", role: .cancel) {
                recordingRecovery.dismissPendingPrompt()
            }
        } message: {
            Text(recordingRecovery.pending?.reason.message ?? "The interrupted recording needs attention.")
        }
        .alert(
            "Delete interrupted recording?",
            isPresented: Bindable(recordingRecovery).isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                recordingRecovery.confirmDeletePending(modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the recovered audio and its recovery record.")
        }
        .alert(
            "Recording recovery could not finish",
            isPresented: Binding(
                get: { recordingRecovery.errorMessage != nil },
                set: { if !$0 { recordingRecovery.errorMessage = nil } }
            )
        ) {
            Button("OK") { recordingRecovery.errorMessage = nil }
        } message: {
            Text(recordingRecovery.errorMessage ?? "Unknown recovery error")
        }
        .preferredColorScheme(settingsVM.preferredColorScheme?.systemColorScheme)
    }
    
    @ViewBuilder
    private var recordingRecoveryBanner: some View {
        if let notice = recordingRecovery.notice {
            Button {
                appState.activeTab = .home
                router.homePath = [.meetingDetail(id: notice.meetingID)]
                recordingRecovery.dismissNotice()
            } label: {
                Label("Recovered a recording that was interrupted", systemImage: "waveform.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityHint("Opens the recovered meeting")
        } else if recordingRecovery.pending != nil {
            Button {
                recordingRecovery.presentPendingPrompt()
            } label: {
                Label("An interrupted recording needs attention", systemImage: "waveform.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
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
                router.navigate(to: .meetingDetail(id: meeting.id), in: .home)
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
            NavigationStack {
                RootAskAISheet(meetingId: id, modelContext: modelContext) { appState.activeSheet = nil }
            }
        }
    }
}
