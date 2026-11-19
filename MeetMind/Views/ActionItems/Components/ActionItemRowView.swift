import SwiftUI

/// Checklist row with a completion control, meeting link, and task metadata.
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
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? Color.accentColor : Theme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Reopen \(item.title)" : "Complete \(item.title)")
            
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
                    if !item.priorityRaw.isEmpty { PriorityBadge(priorityText: item.priority.rawValue) }
                    if let assignee = item.assignee?.name {
                        Text(assignee).font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let due = item.dueDate {
                        Text(due.formatted(date: .abbreviated, time: .omitted))
                            .font(Typography.caption2).foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                if let category = item.category { Text(category).font(.caption).foregroundStyle(.secondary) }
                if let evidence = item.sourceEvidence {
                    DisclosureGroup("Transcript evidence") { Text(evidence).font(.footnote).textSelection(.enabled) }
                        .font(.caption)
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
