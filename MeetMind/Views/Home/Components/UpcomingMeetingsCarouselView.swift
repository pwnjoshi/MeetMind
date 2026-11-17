import SwiftUI

public struct UpcomingMeetingsCarouselView: View {
    public let meetings: [Meeting]
    public var onSelect: ((Meeting) -> Void)? = nil
    public var onStartMeeting: ((Meeting) -> Void)? = nil
    
    public init(
        meetings: [Meeting],
        onSelect: ((Meeting) -> Void)? = nil,
        onStartMeeting: ((Meeting) -> Void)? = nil
    ) {
        self.meetings = meetings
        self.onSelect = onSelect
        self.onStartMeeting = onStartMeeting
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Upcoming Meetings")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Text("\(meetings.count)")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.liveBlue)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.liveBlueLight)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Spacing.lg)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.md) {
                    ForEach(meetings, id: \.id) { meeting in
                        UpcomingMeetingCardView(
                            meeting: meeting,
                            onSelect: { onSelect?(meeting) },
                            onStartMeeting: { onStartMeeting?(meeting) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
            }
        }
    }
}
