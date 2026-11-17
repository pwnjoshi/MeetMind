import SwiftUI

/// Section displaying upcoming scheduled meetings matching Figma node 161:777
public struct HomeUpcomingSectionView: View {
    public let meetings: [Meeting]
    public let onSelect: (Meeting) -> Void
    
    public init(meetings: [Meeting], onSelect: @escaping (Meeting) -> Void) {
        self.meetings = meetings
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming meetings")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color(hex: "#1C1C1E"))
            
            VStack(spacing: 0) {
                if meetings.isEmpty {
                    Text("No upcoming meetings scheduled")
                        .font(Typography.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        MeetingsHomeRowView(
                            title: meeting.title,
                            subtitle: meeting.figmaFormattedSubtitle,
                            categoryBadgeText: meeting.figmaBadgeText,
                            badgeColorHex: meeting.figmaBadgeColorHex,
                            onSelect: { onSelect(meeting) }
                        )
                        if index < meetings.count - 1 {
                            Divider()
                                .padding(.leading, Spacing.md)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#E4E8F1"), lineWidth: 1)
            )
        }
    }
}
