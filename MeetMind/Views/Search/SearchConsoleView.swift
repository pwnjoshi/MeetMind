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
        searchContent.searchable(text: $viewModel.searchQuery, prompt: "Meetings, transcripts, actions")
    }

    private var searchContent: some View {
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
        .onSubmit(of: .search) { viewModel.performSearch(query: viewModel.searchQuery) }
        .onAppear {
            viewModel.setModelContext(modelContext)
            viewModel.indexMeetings(allMeetings)
            viewModel.search(query: viewModel.searchQuery, recordsHistory: false)
        }
        .onChange(of: allMeetings) { _, newMeetings in
            viewModel.indexMeetings(newMeetings)
            viewModel.search(query: viewModel.searchQuery, recordsHistory: false)
        }
        .task(id: viewModel.searchQuery) {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            viewModel.search(query: viewModel.searchQuery, recordsHistory: false)
        }
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

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(viewModel.searchResults) { res in
                    SearchResultRowView(result: res) {
                        viewModel.performSearch(query: viewModel.searchQuery)
                        router.navigate(to: .meetingDetail(id: res.meetingId), in: .search)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
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
