import SwiftUI

/// Bottom floating control bar for pause/resume, finish stop, and discard actions
public struct RecordingControlBarView: View {
    public let isPaused: Bool
    public var onDiscard: () -> Void
    public var onTogglePauseResume: () -> Void
    public var onStop: () -> Void
    
    public init(
        isPaused: Bool,
        onDiscard: @escaping () -> Void,
        onTogglePauseResume: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.isPaused = isPaused
        self.onDiscard = onDiscard
        self.onTogglePauseResume = onTogglePauseResume
        self.onStop = onStop
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xl) {
            Button(action: onDiscard) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 50, height: 50)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.Colors.cardBorder, lineWidth: 1))
            }
            .accessibilityLabel("Discard Recording")
            
            Button(action: onTogglePauseResume) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Theme.Colors.primarySlate)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .accessibilityLabel(isPaused ? "Resume Recording" : "Pause Recording")
            
            Button(action: onStop) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Colors.coralRed)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 50, height: 50)
                .background(Theme.Colors.coralRedLight)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Colors.coralRed.opacity(0.3), lineWidth: 1))
            }
            .accessibilityLabel("Stop Recording")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
    }
}
