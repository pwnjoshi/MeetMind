import SwiftUI

/// Feed card for recent and completed meetings with status badge, star button, AI summary, and action items badge
public struct RecentMeetingCard: View {
    public let meeting: Meeting
    public var onSelect: (() -> Void)? = nil
    public var onToggleStar: (() -> Void)? = nil
    
    public init(meeting: Meeting, onSelect: (() -> Void)? = nil, onToggleStar: (() -> Void)? = nil) {
        self.meeting = meeting
        self.onSelect = onSelect
        self.onToggleStar = onToggleStar
    }
    
    public var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                headerView
                
                Text(meeting.title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if let summary = meeting.summary?.executiveSummary, !summary.isEmpty {
                    Text(summary)
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Divider().padding(.vertical, Spacing.xxs)
                footerView
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous).stroke(Theme.Colors.cardBorder.opacity(0.6), lineWidth: 1))
            .applyShadow(Spacing.Elevation.card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meeting: \(meeting.title)")
    }
    
    private var headerView: some View {
        HStack(alignment: .center) {
            MeetingStatusBadgeView(status: meeting.status)
            Spacer()
            Text(meeting.formattedDate)
                .font(Typography.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
            if let onToggleStar = onToggleStar {
                Button { onToggleStar() } label: {
                    Image(systemName: meeting.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(meeting.isFavorite ? Theme.Colors.warmAmber : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(meeting.isFavorite ? "Unstar meeting" : "Star meeting")
            }
        }
    }
    
    private var footerView: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            if meeting.duration > 0 {
                Label(meeting.formattedDuration, systemImage: "clock").font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if !meeting.participants.isEmpty {
                HStack(spacing: -6) {
                    ForEach(meeting.participants.prefix(3), id: \.id) { s in
                        Circle().fill(Theme.Colors.primarySlate).frame(width: 20, height: 20)
                            .overlay(Text(s.initials).font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                            .overlay(Circle().stroke(Theme.Colors.cardBackground, lineWidth: 1.5))
                    }
                }
            }
            if meeting.pendingActionItemsCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checklist").font(.system(size: 10))
                    Text("\(meeting.pendingActionItemsCount)").font(Typography.caption)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.Colors.warmAmberLight).foregroundStyle(Theme.Colors.warmAmber).clipShape(Capsule())
            }
        }
    }
}
