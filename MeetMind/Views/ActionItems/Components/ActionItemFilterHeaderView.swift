import SwiftUI

/// Header controls for filtering and grouping action items across meetings
public struct ActionItemFilterHeaderView: View {
    public let selectedScope: ActionItemFilterScope
    public let selectedGrouping: ActionItemGrouping
    public let onSelectScope: (ActionItemFilterScope) -> Void
    public let onSelectGrouping: (ActionItemGrouping) -> Void
    
    public init(
        selectedScope: ActionItemFilterScope,
        selectedGrouping: ActionItemGrouping,
        onSelectScope: @escaping (ActionItemFilterScope) -> Void,
        onSelectGrouping: @escaping (ActionItemGrouping) -> Void
    ) {
        self.selectedScope = selectedScope
        self.selectedGrouping = selectedGrouping
        self.onSelectScope = onSelectScope
        self.onSelectGrouping = onSelectGrouping
    }
    
    public var body: some View {
        VStack(spacing: Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(ActionItemFilterScope.allCases, id: \.self) { scope in
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
            }
            
            HStack {
                Text("Group by").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                Picker("Grouping", selection: Binding(get: { selectedGrouping }, set: { onSelectGrouping($0) })) {
                    ForEach(ActionItemGrouping.allCases, id: \.self) { g in
                        Text(g.rawValue.capitalized).tag(g)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
        }
    }
}
