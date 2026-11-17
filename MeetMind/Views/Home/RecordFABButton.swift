import SwiftUI

/// Floating action button with pulsing recording glow for quick meeting recording
public struct RecordFABButton: View {
    public var action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.coralRed)
                    .frame(width: 56, height: 56)
                    .applyShadow(Spacing.Elevation.recordingGlow)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record new meeting")
        .accessibilityHint("Opens quick meeting recording sheet")
    }
}
