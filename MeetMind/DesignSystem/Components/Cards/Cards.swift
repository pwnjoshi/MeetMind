import SwiftUI

// MARK: - Meeting Card
public struct MeetingCardData: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let dateString: String
    public let durationString: String
    public let status: String
    public let summarySnippet: String
    public let actionItemCount: Int
    public let isFavorite: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        dateString: String,
        durationString: String,
        status: String,
        summarySnippet: String,
        actionItemCount: Int = 0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.dateString = dateString
        self.durationString = durationString
        self.status = status
        self.summarySnippet = summarySnippet
        self.actionItemCount = actionItemCount
        self.isFavorite = isFavorite
    }
}

public struct MeetingCard: View {
    public let data: MeetingCardData
    public var onSelect: (() -> Void)? = nil
    
    public init(data: MeetingCardData, onSelect: (() -> Void)? = nil) {
        self.data = data
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center) {
                    StatusBadge(statusText: data.status)
                    Spacer()
                    if data.isFavorite {
                        ImportantBadge()
                    }
                    Text(data.dateString)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Text(data.title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                if !data.summarySnippet.isEmpty {
                    Text(data.summarySnippet)
                        .font(Typography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                HStack(spacing: Spacing.md) {
                    Label(data.durationString, systemImage: "clock")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    if data.actionItemCount > 0 {
                        Label("\(data.actionItemCount) tasks", systemImage: "checklist")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.aiPurple)
                    }
                    
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
            .applyShadow(Spacing.Elevation.card)
            .importantGlowBorder(data.isFavorite, cornerRadius: Spacing.Radius.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Card
public struct ActionCardData: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let isCompleted: Bool
    public let priority: String
    public let dueDateString: String?
    public let assigneeName: String?
    
    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool,
        priority: String,
        dueDateString: String? = nil,
        assigneeName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueDateString = dueDateString
        self.assigneeName = assigneeName
    }
}

public struct ActionCard: View {
    public let data: ActionCardData
    public let onToggle: () -> Void
    
    public init(data: ActionCardData, onToggle: @escaping () -> Void) {
        self.data = data
        self.onToggle = onToggle
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: data.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(data.isCompleted ? Theme.Colors.mintGreen : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(data.title)
                    .font(Typography.body)
                    .foregroundStyle(data.isCompleted ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .strikethrough(data.isCompleted, color: Theme.Colors.textSecondary)
                
                HStack(spacing: Spacing.sm) {
                    PriorityBadge(priorityText: data.priority)
                    
                    if let dueDate = data.dueDateString {
                        Label(dueDate, systemImage: "calendar")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    if let assignee = data.assigneeName {
                        Label(assignee, systemImage: "person.circle")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Summary Card
public struct SummaryCard: View {
    public let executiveSummary: String
    public let keyPoints: [String]
    public var onCopy: (() -> Void)? = nil
    
    public init(executiveSummary: String, keyPoints: [String] = [], onCopy: (() -> Void)? = nil) {
        self.executiveSummary = executiveSummary
        self.keyPoints = keyPoints
        self.onCopy = onCopy
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Executive Summary", systemImage: "sparkles")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.aiPurpleDark)
                Spacer()
                if let onCopy {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.aiPurpleDark)
                    }
                }
            }
            
            Text(executiveSummary)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(4)
            
            if !keyPoints.isEmpty {
                Divider()
                Text("Key Discussion Points")
                    .font(Typography.callout)
                    .bold()
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                ForEach(keyPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text("•")
                            .bold()
                            .foregroundStyle(Theme.Colors.aiPurple)
                        Text(point)
                            .font(Typography.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Theme.Colors.aiPurpleLight.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.lg, style: .continuous)
                .stroke(Theme.Colors.aiPurple.opacity(0.3), lineWidth: 1)
        )
    }
}
