import SwiftUI

public struct RecentMeetingsFeedView: View {
    public let meetings: [Meeting]
    public let isEmpty: Bool
    public let hasEmptyFilterResults: Bool
    public let emptyFilterMessage: String
    public var onSelect: (Meeting) -> Void
    public var onToggleFavorite: (Meeting) -> Void
    public var onDelete: (Meeting) -> Void
    public var onMoveToFolder: (Meeting) -> Void
    
    public init(
        meetings: [Meeting],
        isEmpty: Bool,
        hasEmptyFilterResults: Bool,
        emptyFilterMessage: String,
        onSelect: @escaping (Meeting) -> Void,
        onToggleFavorite: @escaping (Meeting) -> Void,
        onDelete: @escaping (Meeting) -> Void,
        onMoveToFolder: @escaping (Meeting) -> Void
    ) {
        self.meetings = meetings
        self.isEmpty = isEmpty
        self.hasEmptyFilterResults = hasEmptyFilterResults
        self.emptyFilterMessage = emptyFilterMessage
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.onMoveToFolder = onMoveToFolder
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Meetings")
                .font(Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            if isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No meetings yet")
                        .font(Typography.headline)
                    Text("Tap the + button to record, schedule, or import audio.")
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
            } else if hasEmptyFilterResults {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(emptyFilterMessage)
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(meetings, id: \.id) { meeting in
                        RecentMeetingRowView(
                            meeting: meeting,
                            onSelect: { onSelect(meeting) },
                            onToggleFavorite: { onToggleFavorite(meeting) },
                            onDelete: { onDelete(meeting) },
                            onMoveToFolder: { onMoveToFolder(meeting) }
                        )
                    }
                }
            }
        }
    }
}
