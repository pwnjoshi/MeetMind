import SwiftUI

/// Pipeline stage row showing icon, title, description, and status indicator
public struct ProcessingStageRowView: View {
    public let stage: ProcessingStage
    public var onRetry: (() -> Void)? = nil
    
    public init(stage: ProcessingStage, onRetry: (() -> Void)? = nil) {
        self.stage = stage
        self.onRetry = onRetry
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: stage.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconBackground)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(stage.description)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                
                if let warning = stage.warningMessage {
                    Text(warning)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.warmAmber)
                }
                if let error = stage.errorMessage {
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Colors.coralRed)
                }
            }
            Spacer()
            statusIndicator
        }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch stage.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.mintGreen)
                .font(.system(size: 20))
        case .inProgress:
            ProgressView()
                .scaleEffect(0.85)
        case .completedWithWarning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.warmAmber)
                .font(.system(size: 18))
        case .failed:
            if let onRetry = onRetry {
                Button("Retry", action: onRetry)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.coralRed)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Colors.coralRed)
            }
        case .pending:
            Circle()
                .stroke(Theme.Colors.cardBorder, lineWidth: 1.5)
                .frame(width: 18, height: 18)
        }
    }
    
    private var iconColor: Color {
        stage.state == .completed ? Theme.Colors.mintGreen : Theme.Colors.aiPurple
    }
    private var iconBackground: Color {
        stage.state == .completed ? Theme.Colors.mintGreenLight : Theme.Colors.aiPurpleLight
    }
}
