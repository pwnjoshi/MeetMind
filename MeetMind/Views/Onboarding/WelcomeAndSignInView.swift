import SwiftUI

/// Welcome and sign-in screen matching Figma node 161:554 exactly
public struct WelcomeAndSignInView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 700
            VStack(spacing: 0) {
                topIllustrationView(height: isCompact ? 220 : 320)
                signInPanelView
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(hex: "#F2F2F7").ignoresSafeArea())
        }
    }
    
    private func topIllustrationView(height: CGFloat) -> some View {
        ZStack {
            Image("illustration")
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .clipped()
        }
        .frame(height: height)
    }
    
    private var signInPanelView: some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.xs) {
                Text("Welcome to MeetMind")
                    .font(Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: "#1C1C1E"))
                    .multilineTextAlignment(.center)
                Text("From conversation to minutes.\nFrom decisions to action.")
                    .font(Typography.body)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.lg)
            
            SignInEmailInputField(emailText: $viewModel.enteredEmail)
            
            Button {
                viewModel.continueWithEmail()
            } label: {
                Text("Continue with email")
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "#0068D9"))
                    .clipShape(RoundedRectangle(cornerRadius: 25))
            }
            .padding(.top, Spacing.xs)
            
            orDividerView
            SocialAuthButtonsRow(
                onGoogle: { viewModel.continueWithSocialAuth(provider: "Google") },
                onApple: { viewModel.continueWithSocialAuth(provider: "Apple") }
            )
            Spacer(minLength: Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
        .background(Color(hex: "#FCFCFF"))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: -4)
    }
    
    private var orDividerView: some View {
        HStack(spacing: Spacing.md) {
            Rectangle().fill(Color(hex: "#DCDDE4")).frame(height: 1)
            Text("Or continue with")
                .font(Typography.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Rectangle().fill(Color(hex: "#DCDDE4")).frame(height: 1)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
