import SwiftUI

/// Dark waveform visualization card matching Figma node 161:1089
public struct MicWaveformCardView: View {
    public let levels: [Float]
    public init(levels: [Float] = Array(repeating: 0, count: 32)) { self.levels = levels }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#142437"))
                .frame(height: 180)
            
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
                        .animation(.easeInOut(duration: 0.15), value: levels)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let level = levels.indices.contains(index) ? levels[index] : 0
        return 6 + CGFloat(level.isFinite ? max(0, min(1, level)) : 0) * 100
    }
}
