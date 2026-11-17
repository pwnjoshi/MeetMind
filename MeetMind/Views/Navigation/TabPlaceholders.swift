import SwiftUI

/// Temporary placeholder view for Home tab
public struct HomeTabPlaceholderView: View {
    @Environment(AppState.self) private var appState
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Welcome to MeetMind").font(Typography.title1).foregroundStyle(Theme.Colors.textPrimary)
            }.padding(Spacing.lg)
        }.navigationTitle("Home")
    }
}

/// Temporary placeholder view for Action Items tab
public struct ActionItemsTabPlaceholderView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(Theme.Colors.aiPurple)
            Text("Action Items").font(Typography.title2)
        }.navigationTitle("Action Items")
    }
}

/// Temporary placeholder view for Search tab
public struct SearchTabPlaceholderView: View {
    @State private var query: String = ""
    public init() {}
    public var body: some View {
        VStack(spacing: Spacing.lg) {
            SearchBar(text: $query)
            Spacer()
        }.navigationTitle("Search")
    }
}
