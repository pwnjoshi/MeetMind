import SwiftUI

public struct QuickFilterChipsBar: View {
    public let selectedFilter: MeetingFilter
    public let onSelectFilter: (MeetingFilter) -> Void
    
    public init(
        selectedFilter: MeetingFilter,
        onSelectFilter: @escaping (MeetingFilter) -> Void
    ) {
        self.selectedFilter = selectedFilter
        self.onSelectFilter = onSelectFilter
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(MeetingFilter.allCases, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        onSelectFilter(filter)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 12, weight: .medium))
                            Text(filter.title)
                                .font(Typography.callout)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                        .foregroundStyle(isSelected ? Color.white : Theme.Colors.textPrimary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(isSelected ? Theme.Colors.primarySlate : Theme.Colors.secondaryBackground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel("Filter by \(filter.title)")
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedFilter)
    }
}
