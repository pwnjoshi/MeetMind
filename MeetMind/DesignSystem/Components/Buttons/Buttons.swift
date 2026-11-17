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
public struct SecondaryButton: View {
    public let title: String
    public var icon: String? = nil
    public var isEnabled: Bool = true
    public let action: () -> Void
    
    public init(
        title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(title)
                    .font(Typography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(Theme.Colors.primarySlate)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous)
                    .stroke(Theme.Colors.cardBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .disabled(!isEnabled)
    }
}

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
public struct DestructiveButton: View {
    public let title: String
    public var icon: String? = "trash"
    public let action: () -> Void
    
    public init(title: String, icon: String? = "trash", action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    public var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(Typography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(Theme.Colors.coralRed)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md, style: .continuous))
        }
    }
}

// MARK: - Record Pill Button
public struct RecordPillButton: View {
    public let isRecording: Bool
    public let action: () -> Void
    
    public init(isRecording: Bool, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(isRecording ? "Finish Recording" : "Record Meeting")
                    .font(Typography.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(isRecording ? Theme.Colors.coralRed : Theme.Colors.mintGreen)
            .clipShape(Capsule())
            .applyShadow(isRecording ? Spacing.Elevation.recordingGlow : Spacing.Elevation.floating)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isRecording)
        }
    }
}
