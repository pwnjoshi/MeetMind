import SwiftUI

/// 32-bar dynamic waveform visualizer observing 60Hz linear audio power levels
public struct WaveformVisualizerView: View {
    public let levels: [Float]
    public let isRecording: Bool
    
    public init(levels: [Float], isRecording: Bool = true) {
        self.levels = levels
        self.isRecording = isRecording
    }
    
    public var body: some View {
        let displayLevels = normalizedLevels
        
        HStack(alignment: .center, spacing: 3.5) {
            ForEach(0..<displayLevels.count, id: \.self) { idx in
                WaveformBarView(
                    level: displayLevels[idx],
                    isRecording: isRecording
                )
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.Colors.cardBorder.opacity(0.6), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRecording ? "Audio waveform recording" : "Audio waveform paused")
    }
    
    private var normalizedLevels: [Float] {
        if levels.count >= 32 {
            return Array(levels.prefix(32))
        } else {
            return levels + Array(repeating: 0.05, count: 32 - levels.count)
        }
    }
}
