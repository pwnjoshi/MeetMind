import SwiftUI
import SwiftData

/// Meetings, Actions, and cross-meeting Search, each retaining its own stack.
public struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @Query private var actionItems: [ActionItem]
    @State private var searchModel = SearchViewModel()
    
    public init() {}
    
    private var selection: Binding<TabIdentifier> {
        Binding(get: { appState.activeTab }, set: { tab in
            if appState.activeTab == tab { appState.handleTabReselection(tab: tab) }
            else { appState.activeTab = tab }
        })
    }

    public var body: some View {
        Group {
            if #available(iOS 18, *) {
                TabView(selection: selection) {
                    Tab("Meetings", systemImage: "calendar", value: TabIdentifier.home) { meetingsStack }
                    Tab("Actions", systemImage: "flag.fill", value: TabIdentifier.actionItems) { actionsStack }
                        .badge(pendingActionItemsBadge.map { Text($0) })
                    Tab("Search", systemImage: "magnifyingglass", value: TabIdentifier.search, role: .search) { searchStack }
                }
            } else {
                TabView(selection: selection) {
                    meetingsStack.tabItem { Label("Meetings", systemImage: "calendar") }.tag(TabIdentifier.home)
                    actionsStack.tabItem { Label("Actions", systemImage: "flag.fill") }
                        .badge(pendingActionItemsBadge).tag(TabIdentifier.actionItems)
                    searchStack.tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(TabIdentifier.search)
                }
            }
        }
        .tint(Theme.Colors.manentAccent)
    }

    private var meetingsStack: some View {
        NavigationStack(path: Bindable(router).homePath) {
            HomeDashboardView(modelContext: modelContext)
                .navigationDestination(for: NavigationDestination.self) { destinationView(for: $0) }
        }
    }

    private var actionsStack: some View {
        NavigationStack(path: Bindable(router).actionItemsPath) {
            ActionItemsConsoleView(viewModel: ActionItemsViewModel(modelContext: modelContext, remindersService: SystemRemindersSyncService()))
                .navigationDestination(for: NavigationDestination.self) { destinationView(for: $0) }
        }
    }

    private var searchStack: some View {
        NavigationStack(path: Bindable(router).searchPath) {
            SearchConsoleView(viewModel: searchModel)
                .navigationDestination(for: NavigationDestination.self) { destinationView(for: $0) }
        }
    }

    private var pendingActionItemsBadge: String? {
        let uncompletedCount = actionItems.filter { !$0.isCompleted }.count
        let count = uncompletedCount > 0 ? uncompletedCount : appState.actionItemsBadgeCount
        return count <= 0 ? nil : (count > 99 ? "99+" : "\(count)")
    }
    
    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .meetingDetail(let id), .meetingProcessing(let id):
            MeetingDetailContainerView(meetingId: id)
        case .liveRecording(let id):
            LiveRecordingView(meetingId: id)
        case .settings:
            SettingsView()
        }
    }
}
