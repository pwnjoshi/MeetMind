import SwiftUI

public struct GreetingHeaderView: View {
    public var onNotificationTap: (() -> Void)? = nil
    public var onProfileTap: (() -> Void)? = nil
    
    public init(onNotificationTap: (() -> Void)? = nil, onProfileTap: (() -> Void)? = nil) {
        self.onNotificationTap = onNotificationTap
        self.onProfileTap = onProfileTap
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    private var formattedDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Button {
                onProfileTap?()
            } label: {
                Circle()
                    .fill(Theme.Colors.primarySlate)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("MM")
                            .font(Typography.caption)
                            .foregroundStyle(.white)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("User Profile")
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(greetingText)
                    .font(Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(formattedDateText)
                    .font(Typography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            if let onNotificationTap {
                Button(action: onNotificationTap) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(Spacing.sm)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Notifications")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
