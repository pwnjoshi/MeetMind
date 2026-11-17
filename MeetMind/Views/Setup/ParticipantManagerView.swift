import SwiftUI

/// Participant manager component for adding and viewing meeting attendees
public struct ParticipantManagerView: View {
    public let participants: [Speaker]
    public let onAddParticipant: (Speaker) -> Void
    public let onRemoveParticipant: (Speaker) -> Void
    
    @State private var newName: String = ""
    @State private var newRole: String = ""
    
    public init(
        participants: [Speaker],
        onAddParticipant: @escaping (Speaker) -> Void,
        onRemoveParticipant: @escaping (Speaker) -> Void
    ) {
        self.participants = participants
        self.onAddParticipant = onAddParticipant
        self.onRemoveParticipant = onRemoveParticipant
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                TextField("Attendee Name", text: $newName)
                    .font(Typography.body)
                
                Button {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, participants.count < 50 else { return }
                    let speaker = Speaker(name: trimmed, role: newRole.isEmpty ? nil : newRole)
                    onAddParticipant(speaker)
                    newName = ""
                    newRole = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.primarySlate)
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || participants.count >= 50)
                .accessibilityLabel("Add attendee")
            }
            
            if participants.count >= 50 {
                Text("Maximum participant limit (50) reached")
                    .font(Typography.caption2)
                    .foregroundStyle(Theme.Colors.coralRed)
            }
            
            if !participants.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(participants, id: \.id) { speaker in
                            ParticipantTokenChip(speaker: speaker) {
                                onRemoveParticipant(speaker)
                            }
                        }
                    }
                }
            }
        }
    }
}
