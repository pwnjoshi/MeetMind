import SwiftUI
import AVFoundation

/// B1 Microphone permission. Shown once, before the first recording, while
/// the permission is still undetermined. The system prompt follows Allow.
struct MicrophonePermissionView: View {
    let onAllow: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.Colors.manentAccent, in: Circle())
                .accessibilityHidden(true)
            Text("Allow Microphone Access")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Manent records your meetings on this iPhone. Audio never leaves your device.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onAllow) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Theme.Colors.manentAccent, in: Capsule())
            }
            Button("Not Now", action: onNotNow)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
