import SwiftUI

public struct MeetingStatusBadgeView: View {
    public let status: MeetingStatus
    @State private var isPulsing: Bool = false
    
    public init(status: MeetingStatus) {
        self.status = status
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xs) {
            if status == .recording {
                Circle()
                    .fill(Theme.Colors.coralRed)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.25 : 0.85)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
            } else {
                Image(systemName: status.iconName)
                    .font(.system(size: 10, weight: .bold))
            }
            
            Text(status.displayName.uppercased())
                .font(Typography.caption)
        }
        .foregroundStyle(tintColor)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(fillColor)
        .clipShape(Capsule())
        .accessibilityLabel("Status: \(status.displayName)")
    }
    
    private var tintColor: Color {
        switch status {
        case .scheduled: return Theme.Colors.liveBlue
        case .recording: return Theme.Colors.coralRed
        case .processing: return Theme.Colors.warmAmber
        case .completed: return Theme.Colors.mintGreenDark
        case .archived: return Theme.Colors.textSecondary
        }
    }
    
    private var fillColor: Color {
        switch status {
        case .scheduled: return Theme.Colors.liveBlueLight
        case .recording: return Theme.Colors.coralRedLight
        case .processing: return Theme.Colors.warmAmberLight
        case .completed: return Theme.Colors.mintGreenLight
        case .archived: return Theme.Colors.secondaryBackground
        }
    }
}
