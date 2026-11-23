import SwiftUI

/// Dark navy backdrop for the live recording page with three soft light-blue and
/// indigo glows that drift slowly. It stays low contrast so white text remains
/// readable, and it is static when Reduce Motion is on.
struct LiveRecordingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(hex: "#050B1A")
            if reduceMotion {
                Canvas { context, size in
                    Self.drawGlows(&context, size: size, time: 0)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    Canvas { context, size in
                        Self.drawGlows(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color(hex: "#030712").opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static func drawGlows(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let reach = max(size.width, size.height)
        // Each glow: orbit phase offsets, orbit speeds, color, strength, radius factor.
        let glows: [(phaseX: Double, phaseY: Double, speedX: Double, speedY: Double, hex: UInt32, alpha: Double, radius: Double)] = [
            (0.0, 1.3, 0.050, 0.037, 0x4FA3FF, 0.30, 0.62),
            (2.1, 0.4, 0.041, 0.056, 0x5B5BE0, 0.28, 0.70),
            (4.2, 2.6, 0.033, 0.046, 0x38BDF8, 0.18, 0.55)
        ]
        let canvasRect = Path(CGRect(origin: .zero, size: size))
        for glow in glows {
            let x = size.width * (0.5 + 0.38 * sin(time * glow.speedX * 2 * .pi + glow.phaseX))
            let y = size.height * (0.5 + 0.34 * cos(time * glow.speedY * 2 * .pi + glow.phaseY))
            let color = Color(hex: glow.hex)
            let gradient = Gradient(colors: [color.opacity(glow.alpha), color.opacity(0)])
            context.fill(
                canvasRect,
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: x, y: y),
                    startRadius: 0,
                    endRadius: reach * glow.radius
                )
            )
        }
    }
}
