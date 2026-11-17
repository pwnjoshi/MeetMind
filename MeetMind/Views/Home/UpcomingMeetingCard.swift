import SwiftUI

/// Carousel card for an upcoming meeting with countdown badge, attendee avatars, and Start button
public struct UpcomingMeetingCard: View {
    public let meeting: Meeting
    public let countdownText: String
    public var onStartNow: (() -> Void)? = nil
    public var onSelect: (() -> Void)? = nil
    
    public init(meeting: Meeting, countdownText: String = "", onStartNow: (() -> Void)? = nil, onSelect: (() -> Void)? = nil) {
        self.meeting = meeting
        self.countdownText = countdownText
        self.onStartNow = onStartNow
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button { onSelect?() } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Top row: Status badge & countdown badge
                HStack(alignment: .center, spacing: Spacing.sm) {
                    MeetingStatusBadgeView(status: meeting.status)
                    if !countdownText.isEmpty {
                        Text(countdownText)
                            .font(Typography.caption).fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.liveBlue)
                            .padding(.horizontal, Spacing.xs + 2).padding(.vertical, Spacing.xxs)
                            .background(Theme.Colors.liveBlue.opacity(0.12)).clipShape(Capsule())
                    }
                    Spacer()
                }
                
                // Meeting Title
                Text(meeting.title)
                    .font(Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                
                // Attendees & Start Now Button
                HStack(alignment: .center) {
                    if !meeting.participants.isEmpty { attendeeAvatars }
                    Spacer()
                    Button { onStartNow?() } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                            Text("Start Now").font(Typography.caption).fontWeight(.semibold)
                        }
                        .foregroundStyle(.white).padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
                        .background(Theme.Colors.liveBlue).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start meeting now")
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous).stroke(Theme.Colors.cardBorder.opacity(0.6), lineWidth: 1))
            .applyShadow(Spacing.Elevation.card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Upcoming meeting: \(meeting.title)")
    }
    
    private var attendeeAvatars: some View {
        HStack(spacing: -6) {
            ForEach(meeting.participants.prefix(3), id: \.id) { participant in
                Circle().fill(Theme.Colors.primarySlate).frame(width: 24, height: 24)
                    .overlay(Text(participant.initials).font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                    .overlay(Circle().stroke(Theme.Colors.cardBackground, lineWidth: 1.5))
            }
        }
    }
}
