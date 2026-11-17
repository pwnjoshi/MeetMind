import SwiftUI

/// Recent search queries cloud with quick-tap search and clear history
public struct RecentSearchesView: View {
    public let recentSearches: [String]
    public let onSelect: (String) -> Void
    public let onClear: () -> Void
    
    public init(recentSearches: [String], onSelect: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.recentSearches = recentSearches
        self.onSelect = onSelect
        self.onClear = onClear
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Recent Searches")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button("Clear", action: onClear)
                    .font(Typography.caption2)
                    .foregroundStyle(Theme.Colors.coralRed)
            }
            .padding(.horizontal, Spacing.lg)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(recentSearches, id: \.self) { query in
                        Button {
                            onSelect(query)
                        } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                Text(query)
                                    .font(Typography.caption)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Theme.Colors.cardBackground)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.Colors.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }
}
