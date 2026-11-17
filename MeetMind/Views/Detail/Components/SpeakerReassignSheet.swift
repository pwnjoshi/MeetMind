import SwiftUI

/// Modal sheet for reassigning speech segments to another speaker
public struct SpeakerReassignSheet: View {
    public let availableSpeakers: [Speaker]
    public let currentSpeaker: Speaker?
    public let onSelect: (Speaker) -> Void
    public let onDismiss: () -> Void
    
    public init(
        availableSpeakers: [Speaker],
        currentSpeaker: Speaker?,
        onSelect: @escaping (Speaker) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.availableSpeakers = availableSpeakers
        self.currentSpeaker = currentSpeaker
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            List(availableSpeakers) { speaker in
                Button {
                    onSelect(speaker)
                } label: {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .fill(Color(hex: speaker.colorHex))
                            .frame(width: 28, height: 28)
                            .overlay(Text(String(speaker.name.prefix(1))).font(Typography.caption).foregroundStyle(.white))
                        
                        Text(speaker.name)
                            .font(Typography.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Spacer()
                        
                        if speaker.id == currentSpeaker?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.mintGreenDark)
                        }
                    }
                }
            }
            .navigationTitle("Reassign Speaker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
