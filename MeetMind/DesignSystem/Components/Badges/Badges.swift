import SwiftUI

// MARK: - Status Badge
public struct StatusBadge: View {
    public let statusText: String
    public let statusColor: Color?
    
    public init(statusText: String, statusColor: Color? = nil) {
        self.statusText = statusText
        self.statusColor = statusColor
    }
    
    private var badgeColor: (bg: Color, fg: Color, icon: String) {
        if let statusColor = statusColor {
            return (statusColor.opacity(0.15), statusColor, "checkmark.circle.fill")
        }
        switch statusText.lowercased() {
        case "recording":
            return (Theme.Colors.coralRedLight, Theme.Colors.coralRed, "record.circle")
        case "processing":
            return (Theme.Colors.liveBlueLight, Theme.Colors.liveBlue, "arrow.triangle.2.circlepath")
        case "completed":
            return (Theme.Colors.mintGreenLight, Theme.Colors.mintGreenDark, "checkmark.circle.fill")
        case "scheduled":
            return (Theme.Colors.warmAmberLight, Theme.Colors.warmAmber, "calendar")
        case "archived":
            return (Color(uiColor: .tertiarySystemFill), Theme.Colors.textSecondary, "archivebox.fill")
        default:
            return (Color(uiColor: .tertiarySystemFill), Theme.Colors.textSecondary, "circle")
        }
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: badgeColor.icon)
                .font(.system(size: 10, weight: .bold))
            Text(statusText.capitalized)
                .font(Typography.caption)
        }
        .foregroundStyle(badgeColor.fg)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(badgeColor.bg)
        .clipShape(Capsule())
    }
}

// MARK: - Priority Badge
public struct PriorityBadge: View {
    public let priorityText: String
    
    public init(priorityText: String) {
        self.priorityText = priorityText
    }
    
    private var tintColor: Color {
        switch priorityText.lowercased() {
        case "urgent":
            return Theme.Colors.coralRedDark
        case "high":
            return Theme.Colors.coralRed
        case "medium":
            return Theme.Colors.warmAmber
        case "low":
            return Theme.Colors.liveBlue
        default:
            return Theme.Colors.textSecondary
        }
    }
    
    public var body: some View {
        Text(priorityText.uppercased())
            .font(Typography.caption2)
            .bold()
            .foregroundStyle(tintColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(tintColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.sm, style: .continuous))
    }
}
