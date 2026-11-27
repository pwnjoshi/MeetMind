import SwiftUI

// MARK: - Primary Button
public struct PrimaryButton: View {
    public let title: String
    public var icon: String? = nil
    public var isEnabled: Bool = true
    public var isLoading: Bool = false
    public let action: () -> Void
    
    public init(
        title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(title)
                        .font(Typography.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(Theme.Colors.primarySlate)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Secondary Button
// MARK: - Ghost Button
public struct GhostButton: View {
    public let title: String
    public var icon: String? = nil
    public var color: Color = Theme.Colors.primarySlate
    public let action: () -> Void
    
    public init(
        title: String,
        icon: String? = nil,
        color: Color = Theme.Colors.primarySlate,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(Typography.callout)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
    }
}

// MARK: - Destructive Button
// MARK: - Record Pill Button
