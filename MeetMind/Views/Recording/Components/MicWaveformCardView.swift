import SwiftUI

/// Dark waveform visualization card matching Figma node 161:1089
public struct MicWaveformCardView: View {
    public let levels: [Float]
    public let durationText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(levels: [Float] = Array(repeating: 0, count: 32), durationText: String? = nil) {
        self.levels = levels
        self.durationText = durationText
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("“Let’s review the budget and agree on next steps.”")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.clear)
                .frame(height: 60)
            
            HStack(spacing: 4) {
                ForEach(0..<32, id: \.self) { i in
                    let height = barHeight(for: i)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#0068D9"), Color(hex: "#38BDF8")],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: max(6, height))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: levels)
                }
            }
            .padding(.horizontal, 16)
            }
            if let durationText {
                Text(durationText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let level = levels.indices.contains(index) ? levels[index] : 0
        return 6 + CGFloat(level.isFinite ? max(0, min(1, level)) : 0) * 48
    }
}
