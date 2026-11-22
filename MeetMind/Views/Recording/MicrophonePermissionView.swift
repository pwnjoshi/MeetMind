import SwiftUI
import AVFoundation

/// B1 Microphone permission. Shown once, before the first recording, while
/// the permission is still undetermined. The system prompt follows Allow.
/// Styled as the v5 alert-style card over a dimmed backdrop.
struct MicrophonePermissionView: View {
    let onAllow: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            Color.black.opacity(0.28).ignoresSafeArea()
            card
                .padding(.horizontal, 40)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\u{201C}Manent\u{201D} Would Like to Access the Microphone")
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Manent records your meetings on this iPhone. Audio never leaves your device.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                Button(action: onAllow) {
                    Text("Allow")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.manentAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onNotNow) {
                    Text("Don\u{2019}t Allow")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.primary)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
