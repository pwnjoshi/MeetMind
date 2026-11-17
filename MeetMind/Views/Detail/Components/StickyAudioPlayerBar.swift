import SwiftUI

/// Sticky bottom player bar with scrub slider, skip 15s controls, timecodes, and variable speed
public struct StickyAudioPlayerBar: View {
    public let currentTime: TimeInterval
    public let totalDuration: TimeInterval
    public let isPlaying: Bool
    public let playbackRate: Float
    public let onTogglePlayPause: () -> Void
    public let onSeek: (TimeInterval) -> Void
    public let onSkipBackward: () -> Void
    public let onSkipForward: () -> Void
    public let onCycleRate: () -> Void
    
    public init(
        currentTime: TimeInterval,
        totalDuration: TimeInterval,
        isPlaying: Bool,
        playbackRate: Float,
        onTogglePlayPause: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void,
        onSkipBackward: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onCycleRate: @escaping () -> Void
    ) {
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.onTogglePlayPause = onTogglePlayPause
        self.onSeek = onSeek
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
        self.onCycleRate = onCycleRate
    }
    
    public var body: some View {
        VStack(spacing: Spacing.xs) {
            scrubberSection
            controlsSection
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.xl).stroke(Theme.Colors.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: -2)
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }
    
    private var scrubberSection: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { currentTime }, set: { onSeek($0) }), in: 0...max(1.0, totalDuration))
                .tint(Theme.Colors.primarySlate)
            HStack {
                Text(formatTime(currentTime)).font(Typography.timecode).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(formatTime(totalDuration)).font(Typography.timecode).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
    
    private var controlsSection: some View {
        HStack(spacing: Spacing.xl) {
            Button(action: onCycleRate) {
                Text(String(format: "%.2gx", playbackRate)).font(Typography.caption).fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary).padding(.horizontal, Spacing.xs).padding(.vertical, 2)
                    .background(Theme.Colors.secondaryBackground).clipShape(Capsule())
            }
            Spacer()
            Button(action: onSkipBackward) {
                Image(systemName: "gobackward.15").font(.system(size: 20)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Button(action: onTogglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40)).foregroundStyle(Theme.Colors.primarySlate)
            }
            Button(action: onSkipForward) {
                Image(systemName: "goforward.15").font(.system(size: 20)).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)).foregroundStyle(Theme.Colors.textTertiary)
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(interval) / 60, Int(interval) % 60)
    }
}
