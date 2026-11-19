import SwiftUI

/// Sectioned or flat list rendering of action items based on active grouping mode
public struct ActionItemGroupListView: View {
    public let sections: [ActionItemGroupSection]
    public let onToggle: (ActionItem) -> Void
    public let onSelectMeeting: ((UUID) -> Void)?
    public let onOpenTask: ((ActionItem) -> Void)?
    
    public init(
        sections: [ActionItemGroupSection],
        onToggle: @escaping (ActionItem) -> Void,
        onSelectMeeting: ((UUID) -> Void)? = nil,
        onOpenTask: ((ActionItem) -> Void)? = nil
    ) {
        self.sections = sections
        self.onToggle = onToggle
        self.onSelectMeeting = onSelectMeeting
        self.onOpenTask = onOpenTask
    }
    
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(sections) { sec in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if !sec.title.isEmpty {
                            Text(sec.title)
                                .font(Typography.headline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Spacing.lg)
                        }
                        ForEach(sec.items) { item in
                            ActionItemRowView(
                                item: item,
                                onToggle: { onToggle(item) },
                                onSelectMeeting: {
                                    if let id = item.meeting?.id { onSelectMeeting?(id) }
                                },
                                onOpenTask: onOpenTask.map { open in { open(item) } }
                            )
                            .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }
}
