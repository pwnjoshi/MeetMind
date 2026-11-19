import SwiftUI
import SwiftData

/// Dedicated Tab 3 universal cross-meeting search console
public struct SearchConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Query private var allMeetings: [Meeting]
    @State public var viewModel: SearchViewModel
    
    public init(viewModel: SearchViewModel = SearchViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            if viewModel.hasQuery {
                SearchScopeFilterBar(
                    selectedScope: viewModel.selectedScope,
                    onSelectScope: { viewModel.setScope($0) }
                )
            }
            
            if !viewModel.hasQuery && !viewModel.recentSearches.isEmpty {
                RecentSearchesView(
                    recentSearches: viewModel.recentSearches,
                    onSelect: { viewModel.searchQuery = $0; viewModel.performSearch(query: $0) },
                    onClear: { viewModel.recentSearches.removeAll() }
                )
                .padding(.top, Spacing.xs)
            }
            
            if !viewModel.hasQuery && viewModel.recentSearches.isEmpty {
                ContentUnavailableView("Search your meetings", systemImage: "magnifyingglass",
                    description: Text("Find meeting titles, transcript passages, notes, and actions saved on this iPhone."))
            } else if viewModel.hasQuery && viewModel.searchResults.isEmpty {
                emptyResultsView
            } else {
                resultsList
            }
        }
        .background(Color(hex: "#F7F7FC"))
        .navigationTitle("Search")
        .tint(Color(hex: "#4B3FF0"))
        .searchable(text: $viewModel.searchQuery, prompt: "Meetings, transcripts, actions")
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.indexMeetings(allMeetings)
            viewModel.performSearch(query: viewModel.searchQuery)
        }
        .onChange(of: allMeetings) { _, newMeetings in
            viewModel.indexMeetings(newMeetings)
            viewModel.performSearch(query: viewModel.searchQuery)
        }
        .onChange(of: viewModel.searchQuery) { _, newQuery in viewModel.performSearch(query: newQuery) }
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(viewModel.searchResults) { res in
                    SearchResultRowView(result: res) {
                        router.navigate(to: .meetingDetail(id: res.meetingId), in: .search)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No results found for \"\(viewModel.searchQuery)\"")
                .font(Typography.headline)
            Text("Try searching for speaker names, topics, or action items.")
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
