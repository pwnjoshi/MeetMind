import SwiftUI
import SwiftData

/// 4-tab root navigation shell for MeetMind application
public struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Query private var actionItems: [ActionItem]
    
    public init() {}
    
    public var body: some View {
        TabView(selection: Binding(
            get: { appState.activeTab },
            set: { newTab in
                if appState.activeTab == newTab {
                    appState.handleTabReselection(tab: newTab)
                } else {
                    appState.activeTab = newTab
                }
            }
        )) {
            NavigationStack(path: Bindable(router).homePath) {
                HomeDashboardView(modelContext: modelContext)
                    .navigationDestination(for: NavigationDestination.self) { destinationView(for: $0) }
            }
            .tabItem { Label("Meetings", systemImage: "calendar") }
            .tag(TabIdentifier.home)
            
            NavigationStack(path: Bindable(router).actionItemsPath) {
                ActionItemsConsoleView(viewModel: ActionItemsViewModel(modelContext: modelContext, remindersService: SystemRemindersSyncService()))
                    .navigationDestination(for: NavigationDestination.self) { destinationView(for: $0) }
            }
            .tabItem { Label("Actions", systemImage: "flag.fill") }
            .badge(pendingActionItemsBadge)
            .tag(TabIdentifier.actionItems)
        }
        .tint(Color(hex: "#0068D9"))
    }
    
    private var pendingActionItemsBadge: String? {
        let uncompletedCount = actionItems.filter { !$0.isCompleted }.count
        let count = uncompletedCount > 0 ? uncompletedCount : appState.actionItemsBadgeCount
        return count <= 0 ? nil : (count > 99 ? "99+" : "\(count)")
    }
    
    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .meetingDetail(let id):
            MeetingDetailContainerView(meetingId: id)
        case .meetingProcessing(let id):
            MeetingProcessingView(meetingId: id)
        case .liveRecording(let id):
            LiveRecordingView(meetingId: id)
        case .settings:
            SettingsView()
        }
    }
}
