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
    
    /// Speeds the page offers, in order.
    public static let playbackRates: [Float] = [1.0, 1.5, 2.0]

    /// "1×", "1.5×", "2×".
    public static func rateLabel(_ rate: Float) -> String {
        let rounded = rate.rounded()
        let number = abs(rate - rounded) < 0.01 ? String(Int(rounded)) : String(format: "%g", rate)
        return number + "\u{00D7}"
    }

    /// The speed after `rate` when the speed button is tapped. Unknown speeds return to 1×.
    public static func nextRate(after rate: Float) -> Float {
        guard let index = playbackRates.firstIndex(where: { abs($0 - rate) < 0.05 }) else { return 1.0 }
        return playbackRates[(index + 1) % playbackRates.count]
    }

    public var body: some View {
        VStack(spacing: 6) {
            scrubberSection
            controlsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var scrubberSection: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { currentTime }, set: { onSeek($0) }), in: 0...max(1.0, totalDuration))
                .tint(Theme.Colors.manentAccent)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(formatTime(currentTime)) of \(formatTime(totalDuration))")
            HStack {
                Text(formatTime(currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(totalDuration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private var controlsSection: some View {
        HStack(spacing: 28) {
            Button(action: onCycleRate) {
                Text(Self.rateLabel(playbackRate))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .frame(width: 52, height: 32)
                    .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue(Self.rateLabel(playbackRate))
            Spacer(minLength: 0)
            Button(action: onSkipBackward) {
                Image(systemName: "gobackward.15").font(.title3).foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back 15 seconds")
            Button(action: onTogglePlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 42)).foregroundStyle(Theme.Colors.manentAccent)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Button(action: onSkipForward) {
                Image(systemName: "goforward.15").font(.title3).foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Forward 15 seconds")
            Spacer(minLength: 0)
            Color.clear.frame(width: 52, height: 1)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}