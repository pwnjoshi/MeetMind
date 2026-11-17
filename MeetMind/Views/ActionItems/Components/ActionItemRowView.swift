import SwiftUI

/// Universal action item row with round checkmark toggle, meeting link, and metadata pills
public struct ActionItemRowView: View {
    public let item: ActionItem
    public let onToggle: () -> Void
    public let onSelectMeeting: (() -> Void)?
    
    public init(item: ActionItem, onToggle: @escaping () -> Void, onSelectMeeting: (() -> Void)? = nil) {
        self.item = item
        self.onToggle = onToggle
        self.onSelectMeeting = onSelectMeeting
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? Theme.Colors.mintGreenDark : Theme.Colors.cardBorder)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(Typography.headline)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                
                if let meetingTitle = item.meeting?.title {
                    Button {
                        onSelectMeeting?()
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "folder")
                            Text(meetingTitle)
                        }
                        .font(Typography.caption2)
                        .foregroundStyle(Theme.Colors.liveBlue)
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: Spacing.xs) {
                    PriorityBadge(priorityText: item.priority.rawValue)
                    if let assignee = item.assignee?.name {
                        Text(assignee).font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let due = item.dueDate {
                        Text(due.formatted(date: .abbreviated, time: .omitted))
                            .font(Typography.caption2).foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.md).stroke(Theme.Colors.cardBorder, lineWidth: 1))
    }
}
