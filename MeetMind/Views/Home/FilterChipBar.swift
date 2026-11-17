import SwiftUI

/// Horizontal scrolling bar of quick filter chips
public struct FilterChipBar: View {
    @Binding public var selectedFilter: MeetingFilter
    public var onSelectFilter: ((MeetingFilter) -> Void)? = nil
    
    public init(
        selectedFilter: Binding<MeetingFilter>,
        onSelectFilter: ((MeetingFilter) -> Void)? = nil
    ) {
        self._selectedFilter = selectedFilter
        self.onSelectFilter = onSelectFilter
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(MeetingFilter.allCases, id: \.rawValue) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                            onSelectFilter?(filter)
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: filter.iconName)
                                .font(.system(size: 12))
                            Text(filter.title)
                                .font(Typography.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                        .foregroundStyle(isSelected ? Color.white : Theme.Colors.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs + 2)
                        .background(
                            isSelected
                                ? Theme.Colors.primarySlate
                                : Theme.Colors.cardBackground
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected
                                        ? Color.clear
                                        : Theme.Colors.cardBorder.opacity(0.8),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(filter.title) filter")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
        }
    }
}
