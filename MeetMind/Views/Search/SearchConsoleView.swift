import SwiftUI
import SwiftData

/// Dedicated Tab 3 universal cross-meeting search console
public struct SearchConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(AppState.self) private var appState
    @FocusState private var searchFocused: Bool
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
            
            if !viewModel.hasQuery {
                discovery
            } else if viewModel.searchResults.isEmpty {
                emptyResultsView
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .tint(Color(hex: "#4B3FF0"))
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { searchDock }
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

    private var discovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Recent Searches").font(.headline)
                            Spacer()
                            Button("Clear") { viewModel.recentSearches.removeAll() }
                        }
                        .padding(.horizontal, 14)
                        VStack(spacing: 0) {
                            ForEach(viewModel.recentSearches, id: \.self) { query in
                                Button { viewModel.performSearch(query: query) } label: {
                                    Text(query).frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 15).frame(minHeight: 56)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggestions").font(.headline).padding(.horizontal, 14)
                    Button {
                        viewModel.setScope(.transcripts)
                        viewModel.performSearch(query: "Finance")
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Mentions of Finance")
                                Text("In transcripts").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(15)
                    }
                    .buttonStyle(.plain)
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(16)
        }
    }

    private var searchDock: some View {
        HStack(spacing: 8) {
            if !searchFocused {
                Button {
                    appState.activeTab = .home
                } label: {
                    Image(systemName: "calendar").frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Meetings")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Meetings, transcripts, actions", text: $viewModel.searchQuery)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(.regularMaterial, in: Capsule())
            if searchFocused || viewModel.hasQuery {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.setScope(.all)
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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
            Text("No Results for “\(viewModel.searchQuery)”")
                .font(.title3.bold())
            Text("Check the spelling or try a new search.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
