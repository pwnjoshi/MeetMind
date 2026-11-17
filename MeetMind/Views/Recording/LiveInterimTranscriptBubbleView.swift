import SwiftUI

/// Interim speech chunk bubble displaying pending transcription hypotheses
public struct LiveInterimTranscriptBubbleView: View {
    public let text: String
    @State private var isPulsing: Bool = false
    
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(Theme.Colors.liveBlue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .opacity(isPulsing ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            
            Text(text)
                .font(Typography.body)
                .italic()
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Colors.liveBlue.opacity(0.3), lineWidth: 1)
        )
        .onAppear { isPulsing = true }
    }
}
