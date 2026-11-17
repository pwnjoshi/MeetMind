import SwiftUI

/// Header banner displaying the audio waveform icon, title, and descriptive subtitle
public struct AudioImportHeaderView: View {
    public init() {}
    
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            Circle()
                .fill(Theme.Colors.liveBlueLight)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.Colors.liveBlue)
                )
            
            Text("Import Audio Recording")
                .font(Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Transcribe and extract AI action items from .m4a, .mp3, or .wav files.")
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.lg)
    }
}
