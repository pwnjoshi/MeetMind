import SwiftUI

/// Finalized transcript segment bubble with speaker chip, timecode, and text
public struct LiveTranscriptBubbleView: View {
    public let segment: LiveTranscriptSegmentItem
    public var avatarColorHex: String = "#3B82F6"
    @AppStorage(HindiScriptPreference.key) private var hindiScript = HindiScriptStyle.devanagari.rawValue
    
    public init(segment: LiveTranscriptSegmentItem, avatarColorHex: String = "#3B82F6") {
        self.segment = segment
        self.avatarColorHex = avatarColorHex
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color(hex: avatarColorHex))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(speakerInitial)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    )
                
                Text(segment.speakerName)
                    .font(Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Text(formattedTimecode(segment.startTime))
                    .font(Typography.timecode)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            
            Text(HindiScriptPreference.display(segment.text, raw: hindiScript))
                .font(Typography.body)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Colors.cardBorder.opacity(0.6), lineWidth: 1)
        )
    }
    
    private var speakerInitial: String {
        String(segment.speakerName.prefix(1)).uppercased()
    }
    
    private func formattedTimecode(_ time: TimeInterval) -> String {
        let total = Int(time)
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
