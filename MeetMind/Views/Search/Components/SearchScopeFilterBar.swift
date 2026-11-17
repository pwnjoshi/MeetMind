import SwiftUI

/// Horizontal scope filter pills for universal search
public struct SearchScopeFilterBar: View {
    public let selectedScope: SearchScope
    public let onSelectScope: (SearchScope) -> Void
    
    public init(selectedScope: SearchScope, onSelectScope: @escaping (SearchScope) -> Void) {
        self.selectedScope = selectedScope
        self.onSelectScope = onSelectScope
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    let isSelected = scope == selectedScope
                    Button {
                        onSelectScope(scope)
                    } label: {
                        Text(scope.title)
                            .font(Typography.caption)
                            .fontWeight(isSelected ? .bold : .medium)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(isSelected ? Theme.Colors.primarySlate : Theme.Colors.cardBackground)
                            .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Theme.Colors.primarySlate : Theme.Colors.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xxs)
        }
    }
}
