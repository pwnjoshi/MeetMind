import SwiftUI

public struct RecentMeetingRowView: View {
    public let meeting: Meeting
    public let onSelect: () -> Void
    public let onToggleFavorite: () -> Void
    public let onDelete: () -> Void
    public let onMoveToFolder: () -> Void
    
    public init(
        meeting: Meeting,
        onSelect: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onMoveToFolder: @escaping () -> Void
    ) {
        self.meeting = meeting
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.onMoveToFolder = onMoveToFolder
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    MeetingStatusBadgeView(status: meeting.status)
                    Spacer()
                    if meeting.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(Theme.Colors.warmAmber).font(.system(size: 14))
                    }
                    Text(meeting.formattedDate).font(Typography.footnote).foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Text(meeting.title).font(Typography.headline).foregroundStyle(Theme.Colors.textPrimary).lineLimit(2)
                
                if let summary = meeting.summary?.executiveSummary, !summary.isEmpty {
                    Text(summary).font(Typography.subheadline).foregroundStyle(Theme.Colors.textSecondary).lineLimit(2)
                }
                
                HStack(spacing: Spacing.md) {
                    Label(meeting.formattedDuration, systemImage: "clock").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    if meeting.pendingActionItemsCount > 0 {
                        Label("\(meeting.pendingActionItemsCount) tasks", systemImage: "checklist").font(Typography.caption).foregroundStyle(Theme.Colors.aiPurple)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous).stroke(Theme.Colors.cardBorder, lineWidth: 1))
            .applyShadow(Spacing.Elevation.card)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onToggleFavorite) {
                Label(meeting.isFavorite ? "Unstar" : "Star", systemImage: meeting.isFavorite ? "star.slash.fill" : "star.fill")
            }
            .tint(Theme.Colors.warmAmber)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash.fill")
            }
            .tint(Theme.Colors.coralRed)
            
            Button(action: onMoveToFolder) {
                Label("Folder", systemImage: "folder.fill")
            }
            .tint(Theme.Colors.liveBlue)
        }
    }
}
