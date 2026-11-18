import SwiftUI

/// Formatted elapsed timer, pulsing recording dot, and audio route badge
public struct LiveRecordingTimerBadgeView: View {
    public let formattedDuration: String
    public let isRecording: Bool
    public let audioRouteBadgeTitle: String
    
    @State private var isPulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        formattedDuration: String,
        isRecording: Bool,
        audioRouteBadgeTitle: String
    ) {
        self.formattedDuration = formattedDuration
        self.isRecording = isRecording
        self.audioRouteBadgeTitle = audioRouteBadgeTitle
    }
    
    public var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(isRecording ? Theme.Colors.coralRed : Theme.Colors.textSecondary)
                    .frame(width: 10, height: 10)
                    .opacity(isRecording && isPulsing && !reduceMotion ? 0.3 : 1.0)
                    .scaleEffect(isRecording && isPulsing && !reduceMotion ? 1.25 : 1.0)
                    .animation(
                        isRecording && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                        value: isPulsing
                    )
                
                Text(formattedDuration)
                    .font(Typography.timer)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .onAppear { isPulsing = isRecording }
            .onChange(of: isRecording) { _, newValue in isPulsing = newValue }
            
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10, weight: .medium))
                Text(audioRouteBadgeTitle)
                    .font(Typography.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Theme.Colors.liveBlue)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.Colors.liveBlueLight)
            .clipShape(Capsule())
        }
    }
}
