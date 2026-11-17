import SwiftUI
import SwiftData

public struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(NavigationRouter.self) private var router
    @State public var viewModel: HomeViewModel
    
    @State private var meetingToDelete: Meeting? = nil
    @State private var meetingToMove: Meeting? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var isNewMeetingSheetPresented: Bool = false
    
    public init(viewModel: HomeViewModel = HomeViewModel()) { _viewModel = State(initialValue: viewModel) }
    public init(modelContext: ModelContext? = nil) { _viewModel = State(initialValue: HomeViewModel(modelContext: modelContext)) }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    GreetingHeaderView(onNotificationTap: nil, onProfileTap: { appState.activeTab = .settings })
                        .padding(.horizontal, Spacing.lg)
                    SearchBar(text: $viewModel.searchText).padding(.horizontal, Spacing.lg)
                    
                    if !viewModel.filteredUpcomingMeetings.isEmpty {
                        UpcomingMeetingsCarouselView(
                            meetings: viewModel.filteredUpcomingMeetings,
                            onSelect: { router.navigate(to: .meetingDetail(id: $0.id), in: .home) },
                            onStartMeeting: { m in
                                viewModel.transitionStatus(for: m, to: .recording)
                                router.navigate(to: .liveRecording(id: m.id), in: .home)
                            }
                        )
                    }
                    QuickFilterChipsBar(selectedFilter: viewModel.selectedFilter) { f in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { viewModel.setFilter(f) }
                    }
                    RecentMeetingsFeedView(
                        meetings: viewModel.filteredRecentMeetings,
                        isEmpty: viewModel.isEmptyState,
                        hasEmptyFilterResults: viewModel.hasEmptyFilterResults,
                        emptyFilterMessage: viewModel.emptyFilterMessage,
                        onSelect: { router.navigate(to: .meetingDetail(id: $0.id), in: .home) },
                        onToggleFavorite: { viewModel.toggleFavorite(for: $0) },
                        onDelete: { meetingToDelete = $0; showDeleteConfirmation = true },
                        onMoveToFolder: { meetingToMove = $0 }
                    ).padding(.horizontal, Spacing.lg)
                }
                .padding(.vertical, Spacing.md)
            }
            .refreshable { viewModel.fetchMeetings() }
            
            RecordFABButton { isNewMeetingSheetPresented = true }
                .padding([.trailing, .bottom], Spacing.lg)
                .accessibilityLabel("Create New Meeting")
        }
        .background(Theme.Colors.background)
        .navigationBarHidden(true)
        .sheet(isPresented: $isNewMeetingSheetPresented) {
            NewMeetingSheet(modelContext: modelContext) { meeting in
                viewModel.fetchMeetings()
                if meeting.status == .recording { router.navigate(to: .liveRecording(id: meeting.id), in: .home) }
            }
            .environment(\.modelContext, modelContext)
        }
        .sheet(item: $meetingToMove) { meeting in
            FolderTagPickerSheet(meeting: meeting) {
                viewModel.fetchMeetings()
                meetingToMove = nil
            }
            .environment(\.modelContext, modelContext)
        }
        .confirmationDialog("Delete Meeting", isPresented: $showDeleteConfirmation, presenting: meetingToDelete) { meeting in
            Button("Delete Meeting", role: .destructive) { viewModel.deleteMeeting(meeting) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to delete '\($0.title)'?") }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.fetchMeetings()
        }
    }
}
