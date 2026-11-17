import SwiftUI

/// Single diarized transcript segment row with speaker avatar, timestamp, active highlighting, and seek action
public struct TranscriptSegmentRowView: View {
    public let segment: TranscriptSegment
    public let isActive: Bool
    public let onSeek: () -> Void
    public let onEdit: () -> Void
    public let onReassignSpeaker: () -> Void
    
    public init(
        segment: TranscriptSegment,
        isActive: Bool,
        onSeek: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onReassignSpeaker: @escaping () -> Void
    ) {
        self.segment = segment
        self.isActive = isActive
        self.onSeek = onSeek
        self.onEdit = onEdit
        self.onReassignSpeaker = onReassignSpeaker
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(Color(hex: segment.speaker?.colorHex ?? "#3B82F6"))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(String(segment.speaker?.name.prefix(1) ?? "S"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                
                Button(action: onReassignSpeaker) {
                    Text(segment.speaker?.name ?? "Unknown Speaker")
                        .font(Typography.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                
                Button(action: onSeek) {
                    Text(segment.formattedStartTime)
                        .font(Typography.timecode)
                        .foregroundStyle(Theme.Colors.liveBlue)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 1)
                        .background(Theme.Colors.liveBlueLight)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            
            Text(segment.text)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Spacing.xs)
                .background(isActive ? Theme.Colors.liveBlueLight.opacity(0.8) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.sm))
                .onTapGesture { onSeek() }
        }
        .padding(Spacing.sm)
        .background(isActive ? Theme.Colors.cardBackground : Theme.Colors.cardBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.md)
                .stroke(isActive ? Theme.Colors.liveBlue : Color.clear, lineWidth: 1.5)
        )
    }
}
