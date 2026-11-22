import SwiftUI
import SwiftData

/// Dedicated Tab 3 universal cross-meeting search console
public struct SearchConsoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router
    @Environment(SettingsViewModel.self) private var settings
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
                SearchPresentedScopeBar(
                    selected: viewModel.presentedScope,
                    onSelect: { viewModel.setPresentedScope($0) }
                )
                .padding(.horizontal, 16)
            }
            
            if !viewModel.hasQuery {
                discovery
            } else if viewModel.isDebouncing || viewModel.isSearching {
                ProgressView("Searching saved meetings")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let searchError = viewModel.searchErrorMessage {
                ContentUnavailableView {
                    Label("Search Unavailable", systemImage: "exclamationmark.magnifyingglass")
                } description: {
                    Text(searchError)
                } actions: {
                    Button("Try Again") { viewModel.search(query: viewModel.searchQuery, recordsHistory: false) }
                        .buttonStyle(.borderedProminent)
                }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton(tab: .search) }
        }
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
            viewModel.isDebouncing = true
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { viewModel.isDebouncing = false; return }
            viewModel.isDebouncing = false
            viewModel.search(query: viewModel.searchQuery, recordsHistory: false)
        }
    }

    private var discovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Recent").font(.title3.weight(.semibold))
                            Spacer()
                            Button("Clear") { viewModel.recentSearches.removeAll() }
                                .foregroundStyle(Theme.Colors.manentAccent)
                        }
                        .padding(.horizontal, 14)
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.recentSearches.enumerated()), id: \.element) { index, query in
                                Button { viewModel.performSearch(query: query) } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30)
                                            .accessibilityHidden(true)
                                        Text(query).frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 15).frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < viewModel.recentSearches.count - 1 { Divider().padding(.leading, 59) }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }                VStack(alignment: .leading, spacing: 10) {
                    Text("Browse").font(.title3.weight(.semibold)).padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        domainSuggestionRow("Decisions this week", "Decisions saved in meetings this week", suggestion: .decisionsThisWeek, icon: "checkmark.circle.fill", tint: Theme.Colors.manentAccent)
                        Divider().padding(.leading, 59)
                        domainSuggestionRow("Actions assigned to me", "Assigned to \(settings.userProfile?.name ?? UserProfile.defaultLocalName)", suggestion: .actionsAssignedToMe, icon: "checklist", tint: Color.orange)
                        Divider().padding(.leading, 59)
                        suggestionRow("Mentions of Finance", "In transcripts", scope: .transcripts, query: "Finance", icon: "doc.text.fill", tint: Color.teal)
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(16)
        }
    }

    private func domainSuggestionRow(_ title: String, _ subtitle: String, suggestion: SearchSuggestion, icon: String, tint: Color) -> some View {
        Button {
            viewModel.activateSuggestion(
                suggestion,
                localUserName: settings.userProfile?.name ?? UserProfile.defaultLocalName
            )
        } label: {
            suggestionLabel(title, subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func suggestionRow(_ title: String, _ subtitle: String, scope: SearchPresentedScope, query: String, icon: String, tint: Color) -> some View {
        Button {
            viewModel.setPresentedScope(scope)
            viewModel.performSearch(query: query)
        } label: {
            suggestionLabel(title, subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func suggestionLabel(_ title: String, _ subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(15)
        .contentShape(Rectangle())
    }

    private var resultsList: some View {
        SearchResultSectionsView(viewModel: viewModel, meetings: allMeetings) { meetingId in
            viewModel.performSearch(query: viewModel.searchQuery)
            router.navigate(to: .meetingDetail(id: meetingId), in: .search)
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
