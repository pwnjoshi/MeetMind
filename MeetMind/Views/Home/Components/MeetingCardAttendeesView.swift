import SwiftUI

/// Reusable subview displaying attendee initials avatars with overflow badge
public struct MeetingCardAttendeesView: View {
    public let speakers: [Speaker]
    
    public init(speakers: [Speaker]) {
        self.speakers = speakers
    }
    
    public var body: some View {
        HStack(spacing: -6) {
            ForEach(speakers.prefix(3), id: \.id) { speaker in
                Circle()
                    .fill(Theme.Colors.primarySlate)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text(speakerInitials(speaker.name))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.Colors.cardBackground, lineWidth: 1.5)
                    )
            }
            
            if speakers.count > 3 {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Text("+\(speakers.count - 3)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    )
            }
        }
    }
    
    private func speakerInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first, let last = parts.dropFirst().first {
            return "\(first.prefix(1))\(last.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
