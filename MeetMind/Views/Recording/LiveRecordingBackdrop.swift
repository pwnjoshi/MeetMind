import SwiftUI

/// Very dark navy backdrop for the live recording page. Two large static radial
/// glows drift with a slow transform animation (no Canvas, no per-frame redraw, no
/// blur), so the GPU only composites two cached layers. The drift stops under
/// Reduce Motion and whenever the app is not active.
struct LiveRecordingBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var drift = false

    private var shouldAnimate: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x05070F), Color(hex: 0x0A1230)],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let side = max(width, height)
                ZStack {
                    glow(hex: 0x2A4BE0, opacity: 0.25, diameter: side * 1.1)
                        .scaleEffect(drift ? 1.18 : 0.92)
                        .offset(x: drift ? -width * 0.10 : width * 0.18, y: drift ? height * 0.10 : -height * 0.06)
                        .position(x: width * 0.25, y: height * 0.22)
                    glow(hex: 0x4A3FD0, opacity: 0.22, diameter: side * 1.0)
                        .scaleEffect(drift ? 0.92 : 1.15)
                        .offset(x: drift ? width * 0.12 : -width * 0.14, y: drift ? -height * 0.08 : height * 0.10)
                        .position(x: width * 0.78, y: height * 0.78)
                }
                .frame(width: width, height: height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { updateAnimation() }
        .onChange(of: shouldAnimate) { _, _ in updateAnimation() }
    }

    private func glow(hex: UInt32, opacity: Double, diameter: CGFloat) -> some View {
        RadialGradient(
            colors: [Color(hex: hex).opacity(opacity), Color(hex: hex).opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
    }

    private func updateAnimation() {
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                drift = true
            }
        } else {
            // A new, finite animation replaces the repeating one and settles the glows.
            withAnimation(.easeOut(duration: 0.6)) {
                drift = false
            }
        }
    }
}
