import SwiftUI

/// Single animated audio bar in the dynamic waveform visualizer
public struct WaveformBarView: View {
    public let level: Float
    public let isRecording: Bool
    public var maxHeight: CGFloat = 72
    public var minHeight: CGFloat = 6
    public var barWidth: CGFloat = 4.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        level: Float,
        isRecording: Bool = true,
        maxHeight: CGFloat = 72,
        minHeight: CGFloat = 6,
        barWidth: CGFloat = 4.5
    ) {
        self.level = level
        self.isRecording = isRecording
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.barWidth = barWidth
    }
    
    public var body: some View {
        let clampedLevel = isRecording ? CGFloat(max(0.0, min(1.0, level.isFinite ? level : 0.0))) : 0.0
        let height = minHeight + clampedLevel * (maxHeight - minHeight)
        
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(barFill)
            .frame(width: barWidth, height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: height)
    }
    
    private var barFill: Color {
        isRecording ? Color("RecordingWaveform") : Color(uiColor: .separator)
    }
}
