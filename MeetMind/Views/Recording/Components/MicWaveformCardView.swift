import SwiftUI

/// Prompt-and-waveform card on the Test Microphone screen (Figma node 161:1089).
public struct MicWaveformCardView: View {
    public static let promptText = "\u{201C}Let\u{2019}s review the budget and agree on next steps.\u{201D}"
    public let levels: [Float]
    public let durationText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(levels: [Float] = Array(repeating: 0, count: 32), durationText: String? = nil) {
        self.levels = levels
        self.durationText = durationText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Self.promptText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(0..<32, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.manentAccent)
                        .frame(width: 4, height: max(6, barHeight(for: i)))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: levels)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .accessibilityHidden(true)

            if let durationText {
                Text(durationText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = levels.indices.contains(index) ? levels[index] : 0
        return 6 + CGFloat(level.isFinite ? max(0, min(1, level)) : 0) * 48
    }
}
