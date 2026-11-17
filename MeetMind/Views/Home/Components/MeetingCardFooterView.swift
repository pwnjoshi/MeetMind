import SwiftUI

/// Reusable footer component for MeetingCardView showing date, duration, attendees, and action items badge
public struct MeetingCardFooterView: View {
    public let meeting: Meeting
    
    public init(meeting: Meeting) {
        self.meeting = meeting
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            Label(formattedDate(meeting.createdAt), systemImage: "clock")
                .font(Typography.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            if meeting.duration > 0 {
                Text(formatDuration(meeting.duration))
                    .font(Typography.timecode)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            if !meeting.speakers.isEmpty {
                MeetingCardAttendeesView(speakers: meeting.speakers)
            }
            
            actionItemsBadge
        }
    }
    
    @ViewBuilder
    private var actionItemsBadge: some View {
        if !meeting.actionItems.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                Text("\(meeting.actionItems.filter { !$0.isCompleted }.count)")
                    .font(Typography.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.warmAmberLight)
            .foregroundStyle(Theme.Colors.warmAmber)
            .clipShape(Capsule())
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}
