import SwiftUI

/// Search result card showing matched category, snippet text, and jump-to-timecode
public struct SearchResultRowView: View {
    public let result: SearchResultItem
    public let onSelect: () -> Void
    
    public init(result: SearchResultItem, onSelect: @escaping () -> Void) {
        self.result = result
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    categoryBadge
                    Spacer()
                    if let time = result.timecode {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "play.circle.fill")
                            Text(formatTime(time))
                        }
                        .font(Typography.timecode)
                        .foregroundStyle(Theme.Colors.liveBlue)
                    }
                }
                
                Text(result.meetingTitle)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(result.snippet)
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(Spacing.md)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.md).stroke(Theme.Colors.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var categoryBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: categoryIcon)
                .font(.system(size: 10))
            Text(result.category.displayName)
                .font(Typography.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(categoryColor.bg)
        .foregroundStyle(categoryColor.fg)
        .clipShape(Capsule())
    }
    
    private var categoryIcon: String {
        switch result.category {
        case .meetingTitle: return "folder.fill"
        case .transcript: return "waveform"
        case .summary: return "doc.text.fill"
        case .actionItem: return "checklist"
        case .note: return "note.text"
        }
    }
    
    private var categoryColor: (bg: Color, fg: Color) {
        switch result.category {
        case .meetingTitle: return (Theme.Colors.warmAmberLight, Theme.Colors.warmAmber)
        case .transcript: return (Theme.Colors.liveBlueLight, Theme.Colors.liveBlue)
        case .summary: return (Theme.Colors.aiPurpleLight, Theme.Colors.aiPurple)
        case .actionItem: return (Theme.Colors.mintGreenLight, Theme.Colors.mintGreenDark)
        case .note: return (Theme.Colors.warmAmberLight, Theme.Colors.warmAmber)
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let min = Int(interval) / 60
        let sec = Int(interval) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}
