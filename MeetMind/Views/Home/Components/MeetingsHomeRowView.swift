import SwiftUI

/// Tall meeting list row matching Figma node 788:1872 & 788:1929
public struct MeetingsHomeRowView: View {
    public let title: String
    public let subtitle: String
    public let categoryBadgeText: String
    public let badgeColorHex: String
    public let onSelect: () -> Void
    
    public init(
        title: String,
        subtitle: String,
        categoryBadgeText: String,
        badgeColorHex: String = "#5F636B",
        onSelect: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.categoryBadgeText = categoryBadgeText
        self.badgeColorHex = badgeColorHex
        self.onSelect = onSelect
    }
    
    public var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(Color(hex: "#1C1C1E"))
                    Text(subtitle)
                        .font(Typography.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Text(categoryBadgeText)
                        .font(Typography.caption)
                        .foregroundStyle(Color(hex: badgeColorHex))
                        .padding(.top, 1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
