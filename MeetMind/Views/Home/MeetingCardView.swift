import SwiftUI

/// Reusable card displaying meeting details, status, attendee chips, and AI summary preview
public struct MeetingCardView: View {
    public let meeting: Meeting
    public var onSelect: (() -> Void)? = nil
    public var onToggleStar: (() -> Void)? = nil
    
    public init(
        meeting: Meeting,
        onSelect: (() -> Void)? = nil,
        onToggleStar: (() -> Void)? = nil
    ) {
        self.meeting = meeting
        self.onSelect = onSelect
        self.onToggleStar = onToggleStar
    }
    
    public var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header: Status badge & Star button
                HStack(alignment: .center) {
                    MeetingStatusBadgeView(status: meeting.status)
                    
                    Spacer()
                    
                    if let onToggleStar = onToggleStar {
                        Button {
                            onToggleStar()
                        } label: {
                            Image(systemName: meeting.isStarred ? "star.fill" : "star")
                                .font(.system(size: 16))
                                .foregroundStyle(meeting.isStarred ? Theme.Colors.warmAmber : Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Title
                Text(meeting.title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // AI Summary snippet if present
                if let summaryText = meeting.summary?.executiveSummary, !summaryText.isEmpty {
                    Text(summaryText)
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Divider()
                    .padding(.vertical, Spacing.xxs)
                
                // Footer
                MeetingCardFooterView(meeting: meeting)
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous)
                    .stroke(Theme.Colors.cardBorder.opacity(0.6), lineWidth: 1)
            )
            .applyShadow(Spacing.Elevation.card)
        }
        .buttonStyle(.plain)
    }
}
