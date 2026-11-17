import SwiftUI

/// Option card displayed in the New Meeting launcher modal
public struct NewMeetingOptionCard: View {
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let tintColor: Color
    public let backgroundColor: Color
    public var action: () -> Void
    
    public init(
        title: String,
        subtitle: String,
        iconName: String,
        tintColor: Color,
        backgroundColor: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tintColor)
                    )
                
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
            .applyShadow(Spacing.Elevation.card)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(subtitle)")
    }
}
