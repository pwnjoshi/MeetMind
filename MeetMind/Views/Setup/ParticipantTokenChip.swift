import SwiftUI

/// Chip component displaying attendee avatar initials, name, and remove button
public struct ParticipantTokenChip: View {
    public let speaker: Speaker
    public var onRemove: () -> Void
    
    public init(speaker: Speaker, onRemove: @escaping () -> Void) {
        self.speaker = speaker
        self.onRemove = onRemove
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(Theme.Colors.primarySlate)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(speaker.initials)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            
            Text(speaker.name)
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(speaker.name)")
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(Capsule())
    }
}
