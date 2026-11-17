import SwiftUI

/// Dark waveform visualization card matching Figma node 161:1089
public struct MicWaveformCardView: View {
    @State private var phase: Double = 0
    
    public init() {}
    
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
                        .animation(.easeInOut(duration: 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
                phase += 0.3
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalized = sin(phase + Double(index) * 0.45)
        let magnitude = CGFloat(abs(normalized))
        return 16 + magnitude * 85
    }
}
