import SwiftUI

/// Educational card reinforcing MeetMind on-device privacy guarantee
public struct PrivacyGuaranteeCard: View {
    public init() {}
    
    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.mintGreen)
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Your meetings stay with you")
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Recordings, transcripts, and analysis stay on your iPhone. Public model files require a one-time download; meeting analysis then runs offline without an account.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.md).stroke(Theme.Colors.cardBorder, lineWidth: 1))
    }
}
