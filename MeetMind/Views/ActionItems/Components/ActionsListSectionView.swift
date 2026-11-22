import SwiftUI

/// One titled card of action rows ("Yours" or "Waiting on others").
struct ActionsListSectionView: View {
    let title: String
    var titleColor: Color = .primary
    let items: [ActionItem]
    let showsOwner: Bool
    let footer: String?
    let onToggle: (ActionItem) -> Void
    let onOpen: (ActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(titleColor)
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ActionsListRow(
                        item: item,
                        showsOwner: showsOwner,
                        onToggle: { onToggle(item) },
                        onOpen: { onOpen(item) }
                    )
                    if index < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

/// Action row: completion circle, title, due and owner or meeting line, chevron.
struct ActionsListRow: View {
    let item: ActionItem
    let showsOwner: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? Theme.Colors.manentAccent : Color.secondary)
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Reopen \(item.title)" : "Complete \(item.title)")

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                            .strikethrough(item.isCompleted)
                            .multilineTextAlignment(.leading)
                        if let line = subtitle {
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let due = ActionListLogic.dueInfo(for: item) {
                        Text(dueLabel(due))
                            .foregroundStyle(due.isOverdue ? Color.red : Color.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 66)
    }

    /// "Meeting title \u{00B7} Owner".
    private var subtitle: String? {
        var parts: [String] = []
        if let meeting = item.meeting?.title { parts.append(meeting) }
        if let owner = item.assignee?.name { parts.append(owner) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Right-hand due text: time for today's tasks, weekday for this week, short date otherwise.
    private func dueLabel(_ due: ActionDueInfo) -> String {
        guard let date = item.dueDate else { return due.text }
        let calendar = Calendar.current
        let hasTime = calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0
        if calendar.isDateInToday(date) {
            return hasTime ? date.formatted(date: .omitted, time: .shortened) : "Today"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 99
        if days > -7 && days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return ActionListLogic.shortDate(date)
    }
}