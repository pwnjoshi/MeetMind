import SwiftUI

public struct UpcomingMeetingCardView: View {
    public let meeting: Meeting
    public var onSelect: (() -> Void)? = nil
    public var onStartMeeting: (() -> Void)? = nil
    
    public init(
        meeting: Meeting,
        onSelect: (() -> Void)? = nil,
        onStartMeeting: (() -> Void)? = nil
    ) {
        self.meeting = meeting
        self.onSelect = onSelect
        self.onStartMeeting = onStartMeeting
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                MeetingStatusBadgeView(status: meeting.status)
                Spacer()
                if meeting.isFavorite { ImportantBadge(iconOnly: true) }
                Text(meeting.formattedDate)
                    .font(Typography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Text(meeting.title)
                .font(Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: Spacing.xs)
            
            HStack {
                HStack(spacing: -6) {
                    ForEach(meeting.participants.prefix(3), id: \.id) { p in
                        Circle()
                            .fill(Theme.Colors.primarySlate)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(p.initials)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .overlay(Circle().stroke(Theme.Colors.cardBackground, lineWidth: 1.5))
                    }
                    if meeting.participants.count > 3 {
                        Circle()
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("+\(meeting.participants.count - 3)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            )
                    }
                }
                
                Spacer()
                
                Button {
                    onStartMeeting?()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "record.circle.fill")
                        Text("Start")
                    }
                    .font(Typography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.Colors.coralRed)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(Spacing.lg)
        .frame(width: 280, height: 150)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
        .applyShadow(Spacing.Elevation.card)
        .importantGlowBorder(meeting.isFavorite, cornerRadius: Spacing.Radius.lg)
        .onTapGesture {
            onSelect?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Upcoming meeting \(meeting.title) on \(meeting.formattedDate)")
    }
}
