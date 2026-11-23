import SwiftUI

/// Section displaying recent meetings feed matching Figma node 161:777
public struct HomeRecentSectionView: View {
    public let meetings: [Meeting]
    public let onSelect: (Meeting) -> Void
    
    public init(meetings: [Meeting], onSelect: @escaping (Meeting) -> Void) {
        self.meetings = meetings
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent meetings")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            
            VStack(spacing: 0) {
                if meetings.isEmpty {
                    Text("No recent meetings")
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
                            isImportant: meeting.isFavorite,
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
            .clipShape(RoundedRectangle(cornerRadius: 20))

        }
    }
}
