import SwiftUI

/// Expandable voice baseline recording card
public struct VoiceBaselineCardView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: viewModel.hasVoiceBaseline ? "checkmark.circle.fill" : "waveform.badge.mic")
                    .font(.system(size: 24))
                    .foregroundStyle(viewModel.hasVoiceBaseline ? Theme.Colors.mintGreen : Theme.Colors.liveBlue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Baseline Signature")
                        .font(Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(viewModel.hasVoiceBaseline ? "Sample voice signature recorded" : "Optional 5-second sample for speaker identification")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                actionButton
            }
            
            if viewModel.isRecordingVoiceBaseline {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Theme.Colors.coralRed)
                        .frame(width: 8, height: 8)
                    Text("Recording voice sample... Say: 'Hello, this is my meeting voice.'")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.Colors.coralRed)
                }
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.md)
                .stroke(Theme.Colors.cardBorder, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if viewModel.isRecordingVoiceBaseline {
            Button("Done") { viewModel.stopVoiceBaselineRecording() }
                .font(Typography.subheadline)
                .foregroundStyle(Theme.Colors.coralRed)
        } else if viewModel.hasVoiceBaseline {
            Button("Redo") { viewModel.startVoiceBaselineRecording() }
                .font(Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        } else {
            Button("Record") { viewModel.startVoiceBaselineRecording() }
                .font(Typography.subheadline)
                .foregroundStyle(Theme.Colors.liveBlue)
        }
    }
}
