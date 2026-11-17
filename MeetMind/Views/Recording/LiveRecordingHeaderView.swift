import SwiftUI

/// Header displaying meeting title, live badge, and console controls
public struct LiveRecordingHeaderView: View {
    @Binding public var title: String
    public let isOfflineFallback: Bool
    public var onDismiss: () -> Void
    
    @State private var isEditingTitle: Bool = false
    
    public init(
        title: Binding<String>,
        isOfflineFallback: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self._title = title
        self.isOfflineFallback = isOfflineFallback
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss Recording Console")
            
            VStack(alignment: .leading, spacing: 2) {
                if isEditingTitle {
                    TextField("Meeting Title", text: $title)
                        .font(Typography.headline)
                        .textFieldStyle(.plain)
                        .onSubmit { isEditingTitle = false }
                } else {
                    Text(title.isEmpty ? "Live Meeting" : title)
                        .font(Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .onTapGesture { isEditingTitle = true }
                }
                
                HStack(spacing: 6) {
                    Text("LIVE RECORDING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.coralRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.coralRedLight)
                        .clipShape(Capsule())
                    
                    if isOfflineFallback {
                        Text("Offline Engine")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Colors.warmAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.warmAmberLight)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
    }
}
