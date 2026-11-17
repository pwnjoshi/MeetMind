import SwiftUI

/// Reusable bulleted points card for decisions and discussion topics in summary tab
public struct MeetingSummaryPointsCard: View {
    public let title: String
    public let icon: String
    public let tintColor: Color
    public let backgroundColor: Color
    public let items: [String]
    
    public init(title: String, icon: String, tintColor: Color, backgroundColor: Color, items: [String]) {
        self.title = title
        self.icon = icon
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
        self.items = items
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(title, systemImage: icon)
                .font(Typography.headline)
                .foregroundStyle(tintColor)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("•").bold().foregroundStyle(tintColor)
                    Text(item).font(Typography.body).foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(Spacing.md)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.lg))
    }
}
