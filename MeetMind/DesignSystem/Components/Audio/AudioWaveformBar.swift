import SwiftUI

/// Reactive Audio Waveform Bar
/// Can be rendered as a single bar or grouped in a 32-bar visualizer stack
public struct AudioWaveformBar: View {
    public let level: Float // Normalized 0.0 ... 1.0
    public var maxHeight: CGFloat = 80
    public var minHeight: CGFloat = 6
    public var barWidth: CGFloat = 4
    public var activeColor: Color = Theme.Colors.liveBlue
    public var inactiveColor: Color = Theme.Colors.cardBorder
    public var isActive: Bool = true
    
    public init(
        level: Float,
        maxHeight: CGFloat = 80,
        minHeight: CGFloat = 6,
        barWidth: CGFloat = 4,
        activeColor: Color = Theme.Colors.liveBlue,
        inactiveColor: Color = Theme.Colors.cardBorder,
        isActive: Bool = true
    ) {
        self.level = level
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.barWidth = barWidth
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.isActive = isActive
    }
    
    private var computedHeight: CGFloat {
        let clamped = max(0.0, min(1.0, level.isFinite ? level : 0.0))
        return minHeight + CGFloat(clamped) * (maxHeight - minHeight)
    }
    
    public var body: some View {
        RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
            .fill(isActive ? activeColor : inactiveColor)
            .frame(width: barWidth, height: computedHeight)
            .animation(.easeInOut(duration: 0.1), value: computedHeight)
    }
}
