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
            List(availableSpeakers, id: \.id) { speaker in
                Button {
                    onSelect(speaker)
                } label: {
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .fill(Color(hex: speaker.colorHex))
                            .frame(width: 28, height: 28)
                            .overlay(Text(speaker.initials).font(.caption2.weight(.bold)).foregroundStyle(.white))
                        
                        Text(speaker.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if speaker.id == currentSpeaker?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.manentAccent)
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
