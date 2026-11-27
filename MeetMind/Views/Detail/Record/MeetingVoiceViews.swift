import SwiftUI

/// One detected voice in the People sheet: name, talk time, turns, two or three clips of the
/// voice to listen to, and the menu that assigns the voice to a person.
@MainActor
struct MeetingVoiceCard<AssignMenu: View>: View {
    let row: MeetingVoiceRow
    let displayName: String
    let stats: MeetingVoiceStats
    let samples: [MeetingVoiceSample]
    let canPlay: Bool
    let player: VoiceSamplePlayer
    let onToggle: (MeetingVoiceSample) -> Void
    @ViewBuilder let assignMenu: () -> AssignMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if samples.isEmpty {
                Text("No clear clip of this voice to play.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(samples) { sample in
                    MeetingVoiceSampleRow(
                        sample: sample,
                        canPlay: canPlay,
                        isPlaying: player.isPlaying(sample),
                        onToggle: { onToggle(sample) }
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.subheadline.weight(.semibold))
                Text(stats.summaryText).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            assignMenu()
        }
    }
}

/// A single playable clip: play/stop button, start time and the words spoken.
@MainActor
struct MeetingVoiceSampleRow: View {
    let sample: MeetingVoiceSample
    let canPlay: Bool
    let isPlaying: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if canPlay {
                Button(action: onToggle) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.manentAccent)
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.manentAccent.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isPlaying ? "Stop clip at \(sample.timestampText)" : "Play clip at \(sample.timestampText)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.timestampText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\u{201C}\(sample.text)\u{201D}")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(.top, canPlay ? 4 : 0)
            Spacer(minLength: 0)
        }
    }
}
