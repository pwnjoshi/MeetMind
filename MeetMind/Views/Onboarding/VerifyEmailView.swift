import SwiftUI

/// Verify email screen matching Figma node 161:624
public struct VerifyEmailView: View {
    @Bindable public var viewModel: OnboardingViewModel
    @State private var isCodeResent: Bool = false
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            topNavigationHeader
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    headerTextView
                    OtpDigitsRowView(digits: viewModel.verificationDigits)
                    actionButtonsRow
                    verifyContinueButton
                    if isCodeResent {
                        Text("New code sent to \(viewModel.enteredEmail)")
                            .font(Typography.caption)
                            .foregroundStyle(Color(hex: "#0068D9"))
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
            }
        }
        .background(Color(hex: "#F2F2F7").ignoresSafeArea())
    }
    
    private var topNavigationHeader: some View {
        HStack {
            Button(action: viewModel.backToSignIn) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0068D9"))
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .systemBackground).opacity(0.8))
                    .clipShape(Circle())
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
    }
    
    private var headerTextView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 38))
                .foregroundStyle(Color(hex: "#0068D9"))
            Text("Verify your email")
                .font(Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color(hex: "#1C1C1E"))
            Text("Enter the 6-digit code sent to \(viewModel.enteredEmail.isEmpty ? "pawan@apple.com" : viewModel.enteredEmail)")
                .font(Typography.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var actionButtonsRow: some View {
        HStack(spacing: Spacing.md) {
            Button("Resend code") { withAnimation { isCodeResent = true } }
                .font(Typography.subheadline)
                .foregroundStyle(Color(hex: "#0068D9"))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button("Change email", action: viewModel.backToSignIn)
                .font(Typography.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var verifyContinueButton: some View {
        Button(action: viewModel.verifyCodeAndContinue) {
            Text("Verify and continue")
                .font(Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "#0068D9"))
                .clipShape(RoundedRectangle(cornerRadius: 25))
        }
        .padding(.top, Spacing.xs)
    }
}
