import SwiftUI

/// One titled card of action rows ("Yours" or "Waiting on others").
struct ActionsListSectionView: View {
    let title: String
    let items: [ActionItem]
    let showsOwner: Bool
    let footer: String?
    let onToggle: (ActionItem) -> Void
    let onOpen: (ActionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
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
                        if showsOwner {
                            detailLine(trailing: item.assignee?.name)
                            if let meeting = item.meeting?.title {
                                Text(meeting)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            detailLine(trailing: item.meeting?.title)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func detailLine(trailing: String?) -> some View {
        HStack(spacing: 0) {
            if let due = ActionListLogic.dueInfo(for: item) {
                Text(due.text)
                    .foregroundStyle(due.isOverdue ? Color.red : Color.secondary)
                if trailing != nil {
                    Text(" · ").foregroundStyle(.secondary)
                }
            }
            if let trailing {
                Text(trailing).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
    }
}
