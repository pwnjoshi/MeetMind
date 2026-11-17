import SwiftUI

/// Header component for the Home Dashboard displaying time-based greeting, user name, and profile avatar
public struct HomeHeaderView: View {
    public var userName: String
    public var onProfileTap: (() -> Void)? = nil
    
    public init(userName: String = "User", onProfileTap: (() -> Void)? = nil) {
        self.userName = userName
        self.onProfileTap = onProfileTap
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good morning"
        } else if hour < 17 {
            return "Good afternoon"
        } else {
            return "Good evening"
        }
    }
    
    public var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(greeting)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Text(userName)
                    .font(Typography.title2)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            
            Spacer()
            
            Button {
                onProfileTap?()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.primarySlate)
                        .frame(width: 40, height: 40)
                    
                    Text(String(userName.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile settings")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }
}
