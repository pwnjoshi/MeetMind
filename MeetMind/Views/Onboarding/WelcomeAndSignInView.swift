import SwiftUI

/// Manent welcome screen. The visual language follows the product design while entry stays local-only.
public struct WelcomeAndSignInView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(hex: "#EFEFFE"), Color(hex: "#F7F7FC"), .white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    Image("ManentLogo")
                        .resizable().interpolation(.high)
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                        .shadow(color: Color(hex: "#3B2EC9").opacity(0.30), radius: 16, y: 12)
                        .background {
                            ZStack {
                                Circle().stroke(Color(hex: "#E8E8FF")).frame(width: proxy.size.width * 1.04)
                                Circle().stroke(Color(hex: "#DDDDFC")).frame(width: proxy.size.width * 0.75)
                            }
                        }
                        .accessibilityHidden(true)
                    Text("Manent")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#1E1B4B"))
                        .padding(.top, 34)
                    Text("Words fly. Manent stays.")
                        .font(.system(size: 19))
                        .foregroundStyle(Color.secondary)
                        .padding(.top, 6)
                    Spacer()
                    Text("Your recordings stay on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        Button { viewModel.continueLocally() } label: {
                            Label("Continue with Apple", systemImage: "apple.logo")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(.black, in: Capsule())
                        }
                        Button { viewModel.continueLocally() } label: {
                            Text("Continue with Email")
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color(hex: "#ECECEF"), in: Capsule())
                        }
                        Button("Not Now") { viewModel.completeOnboarding() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.top, 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.manentAccent)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
    
}
