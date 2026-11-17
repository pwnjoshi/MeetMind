import SwiftUI

/// Email text input field container for sign in matching Figma node 404:635
public struct SignInEmailInputField: View {
    @Binding public var emailText: String
    
    public init(emailText: Binding<String>) {
        self._emailText = emailText
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Email address")
                .font(Typography.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            TextField("Email address", text: $emailText)
                .font(Typography.body)
                .foregroundStyle(Color(uiColor: .label))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#F0F3FA"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#E4E8F1"), lineWidth: 1))
    }
}

/// Social authentication buttons matching Figma node 735:1478
public struct SocialAuthButtonsRow: View {
    public let onGoogle: () -> Void
    public let onApple: () -> Void
    
    public init(onGoogle: @escaping () -> Void, onApple: @escaping () -> Void) {
        self.onGoogle = onGoogle
        self.onApple = onApple
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onGoogle) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "globe")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "#005BCD"))
                    Text("Google")
                        .font(Typography.headline)
                        .foregroundStyle(Color(hex: "#15233E"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(hex: "#F4F6FB"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#DFE4EF"), lineWidth: 1))
            }
            
            Button(action: onApple) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                    Text("Apple")
                        .font(Typography.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
