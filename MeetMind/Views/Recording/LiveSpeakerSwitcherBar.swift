import SwiftUI

/// Horizontal chip bar for real-time speaker attribution and speaker management
public struct LiveSpeakerSwitcherBar: View {
    public let speakers: [SpeakerItem]
    public let activeSpeakerName: String?
    public var onSelectSpeaker: (SpeakerItem) -> Void
    public var onAddSpeaker: () -> Void
    
    public init(
        speakers: [SpeakerItem],
        activeSpeakerName: String?,
        onSelectSpeaker: @escaping (SpeakerItem) -> Void,
        onAddSpeaker: @escaping () -> Void
    ) {
        self.speakers = speakers
        self.activeSpeakerName = activeSpeakerName
        self.onSelectSpeaker = onSelectSpeaker
        self.onAddSpeaker = onAddSpeaker
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(speakers) { speaker in
                    let isSelected = speaker.name == activeSpeakerName
                    Button { onSelectSpeaker(speaker) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: speaker.colorHex))
                                .frame(width: 14, height: 14)
                            Text(speaker.name)
                                .font(Typography.subheadline)
                                .fontWeight(isSelected ? .bold : .medium)
                                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background(isSelected ? Theme.Colors.liveBlueLight : Theme.Colors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(
                                isSelected ? Theme.Colors.liveBlue : Theme.Colors.cardBorder,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                        )
                        .contentShape(Capsule())
                    }
                }
                
                Button(action: onAddSpeaker) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(Typography.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.liveBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(minHeight: 44)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.Colors.liveBlue.opacity(0.4), lineWidth: 1))
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
        }
    }
}
