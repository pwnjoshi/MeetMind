import SwiftUI

/// Single checklist row in meeting detail action items tab
public struct MeetingActionItemRow: View {
    public let item: ActionItem
    public let onToggle: () -> Void
    
    public init(item: ActionItem, onToggle: @escaping () -> Void) {
        self.item = item
        self.onToggle = onToggle
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
                
                HStack(spacing: Spacing.xs) {
                    if !item.priorityRaw.isEmpty { PriorityBadge(priorityText: item.priority.rawValue) }
                    if let assignee = item.assignee?.name {
                        Text(assignee).font(Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let due = item.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
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
    }
}
