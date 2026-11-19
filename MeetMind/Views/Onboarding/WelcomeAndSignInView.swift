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
                LinearGradient(colors: [Color(hex: "#EEF0FF"), Color(hex: "#F7F7FC"), .white], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Circle().stroke(Color(hex: "#DDDDFC"), lineWidth: 1).frame(width: proxy.size.width * 1.04)
                    .offset(y: -150).accessibilityHidden(true)
                Circle().stroke(Color(hex: "#E8E8FF"), lineWidth: 1).frame(width: proxy.size.width * 0.75)
                    .offset(y: -120).accessibilityHidden(true)

                VStack(spacing: 0) {
                    Spacer(minLength: 46)
                    Image("ManentLogo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                        .shadow(color: Color(hex: "#3B2EC9").opacity(0.30), radius: 16, y: 12)
                        .accessibilityHidden(true)
                    Text("Manent")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#1E1B4B"))
                        .padding(.top, 28)
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
                            Label("Continue on this iPhone", systemImage: "iphone")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)
                        .controlSize(.large)
                        Button("Not Now") { viewModel.completeOnboarding() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
    
}
