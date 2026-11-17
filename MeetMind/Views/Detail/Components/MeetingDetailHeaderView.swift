import SwiftUI

/// Header for the meeting detail cockpit showing title, duration, status, and menu actions
public struct MeetingDetailHeaderView: View {
    public let title: String
    public let durationText: String
    public let statusTitle: String
    public let onRename: () -> Void
    public let onExport: () -> Void
    public let onAskAI: () -> Void
    public let onDelete: () -> Void
    
    public init(
        title: String,
        durationText: String,
        statusTitle: String,
        onRename: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onAskAI: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.title = title
        self.durationText = durationText
        self.statusTitle = statusTitle
        self.onRename = onRename
        self.onExport = onExport
        self.onAskAI = onAskAI
        self.onDelete = onDelete
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                StatusBadge(statusText: statusTitle)
                
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(durationText)
                        .font(Typography.timecode)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Spacing.xs)
                
                Spacer()
                
                Button(action: onAskAI) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "sparkles")
                        Text("Ask AI")
                    }
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.aiPurple)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(Theme.Colors.aiPurpleLight)
                    .clipShape(Capsule())
                }
                
                Menu {
                    Button(action: onRename) { Label("Rename", systemImage: "pencil") }
                    Button(action: onExport) { Label("Export Minutes", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            
            Text(title)
                .font(Typography.title1)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }
}
