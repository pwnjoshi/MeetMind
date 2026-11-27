import SwiftUI

/// Floating glass audio player at the bottom of the Transcript page.
struct TranscriptPlayerBar: View {
    @ObservedObject var audio: TranscriptAudioController
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            if let message = audio.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.coralRedDark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            scrubber
            HStack {
                Text(TranscriptClock.text(shownTime))
                Spacer()
                Text(TranscriptClock.text(audio.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityHidden(true)
            controls
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
    }

    private var shownTime: TimeInterval { isScrubbing ? scrubValue : audio.currentTime }

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { min(max(0, isScrubbing ? scrubValue : audio.currentTime), max(audio.duration, 0.1)) },
                set: { scrubValue = $0 }
            ),
            in: 0...max(audio.duration, 0.1),
            onEditingChanged: { editing in
                if editing {
                    scrubValue = audio.currentTime
                    isScrubbing = true
                } else {
                    audio.seek(to: scrubValue)
                    isScrubbing = false
                }
            }
        )
        .tint(Theme.Colors.manentAccent)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(TranscriptClock.spoken(shownTime)) of \(TranscriptClock.spoken(audio.duration))")
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: Spacing.xl) {
                Button { audio.skip(by: -15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back 15 seconds")

                Button { audio.toggle() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Theme.Colors.manentAccent))
                }
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")

                Button { audio.skip(by: 15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Forward 15 seconds")
            }
            HStack {
                Spacer()
                Button { audio.cycleRate() } label: {
                    Text(StickyAudioPlayerBar.rateLabel(audio.rate))
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Playback speed, \(StickyAudioPlayerBar.rateLabel(audio.rate))")
                .accessibilityHint("Changes the speed")
            }
        }
    }
}

/// Shown instead of the player when the recording file is missing.
struct TranscriptAudioUnavailableBar: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "speaker.slash")
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Audio not available on this iPhone")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
