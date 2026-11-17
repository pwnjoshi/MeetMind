import SwiftUI

/// Circular animated progress ring with percentage display
public struct ProcessingProgressRingView: View {
    public let progress: Double
    public var ringSize: CGFloat = 130
    public var strokeWidth: CGFloat = 10
    
    public init(progress: Double, ringSize: CGFloat = 130, strokeWidth: CGFloat = 10) {
        self.progress = progress
        self.ringSize = ringSize
        self.strokeWidth = strokeWidth
    }
    
    public var body: some View {
        let clamped = max(0.0, min(1.0, progress))
        
        ZStack {
            Circle()
                .stroke(Theme.Colors.cardBorder, lineWidth: strokeWidth)
                .frame(width: ringSize, height: ringSize)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(clamped))
                .stroke(
                    LinearGradient(
                        colors: [Theme.Colors.liveBlue, Theme.Colors.aiPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize, height: ringSize)
                .animation(.easeInOut(duration: 0.3), value: clamped)
            
            VStack(spacing: 2) {
                Text("\(Int(clamped * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Synthesizing")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
