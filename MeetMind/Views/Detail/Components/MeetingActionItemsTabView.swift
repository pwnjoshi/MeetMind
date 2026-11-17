import SwiftUI

/// Action Items tab displaying interactive checklist, assignees, priorities, and Reminders sync
public struct MeetingActionItemsTabView: View {
    public let items: [ActionItem]
    public let onToggle: (ActionItem) -> Void
    public let onAdd: () -> Void
    public let onSyncReminders: () -> Void
    
    public init(
        items: [ActionItem],
        onToggle: @escaping (ActionItem) -> Void,
        onAdd: @escaping () -> Void,
        onSyncReminders: @escaping () -> Void
    ) {
        self.items = items
        self.onToggle = onToggle
        self.onAdd = onAdd
        self.onSyncReminders = onSyncReminders
    }
    
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            topControlBar
            
            if items.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No action items for this meeting").font(Typography.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(items) { item in
                            MeetingActionItemRow(item: item, onToggle: { onToggle(item) })
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
    }
    
    private var topControlBar: some View {
        HStack {
            Button(action: onSyncReminders) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync to Apple Reminders")
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.aiPurple)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Theme.Colors.aiPurpleLight)
                .clipShape(Capsule())
            }
            Spacer()
            Button(action: onAdd) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Task")
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.primarySlate)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }
}
