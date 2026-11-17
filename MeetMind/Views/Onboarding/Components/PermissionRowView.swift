import SwiftUI

/// Educational row for a single system permission
public struct PermissionRowView: View {
    public let permission: PermissionType
    public let title: String
    public let description: String
    public let iconName: String
    public let iconColor: Color
    public let status: PermissionStatus
    public let onRequest: () -> Void
    public let onOpenSettings: () -> Void
    
    public init(
        permission: PermissionType,
        title: String,
        description: String,
        iconName: String,
        iconColor: Color,
        status: PermissionStatus,
        onRequest: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.permission = permission
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconColor = iconColor
        self.status = status
        self.onRequest = onRequest
        self.onOpenSettings = onOpenSettings
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(description)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            statusActionControl
        }
        .padding(Spacing.md)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Spacing.Radius.md).stroke(Theme.Colors.cardBorder, lineWidth: 1))
    }
    
    @ViewBuilder
    private var statusActionControl: some View {
        switch status {
        case .authorized:
            StatusBadge(statusText: "Allowed", statusColor: Theme.Colors.mintGreen)
        case .denied, .restricted:
            Button("Settings") { onOpenSettings() }
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.coralRed)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Theme.Colors.coralRed.opacity(0.1))
                .clipShape(Capsule())
        case .notDetermined:
            Button("Allow") { onRequest() }
                .font(Typography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.primarySlate)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Theme.Colors.primarySlate.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}
