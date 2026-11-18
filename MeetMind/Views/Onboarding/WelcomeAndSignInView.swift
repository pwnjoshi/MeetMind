import SwiftUI

/// Screenshot-based welcome screen with local, account-free entry.
public struct WelcomeAndSignInView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 700
            ScrollView {
                VStack(spacing: 0) {
                    topIllustrationView(height: isCompact ? 240 : 350)
                        .frame(width: proxy.size.width)
                        .clipped()
                        .padding(.bottom, -20)
                    signInPanelView
                        .frame(minHeight: max(0, proxy.size.height - (isCompact ? 220 : 330)))
                }
                .frame(width: proxy.size.width)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(hex: "#FCFCFF").ignoresSafeArea())
        }
        .ignoresSafeArea()
    }
    
    private func topIllustrationView(height: CGFloat) -> some View {
        ZStack {
            Image("MeetingIllustration")
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
                Text("Welcome to\nMeetMind")
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
            
            Text("Your recordings stay on this iPhone.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 16)
            Spacer(minLength: 80)

            Button {
                viewModel.continueLocally()
            } label: {
                Text("Continue on this iPhone")
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(hex: "#0068D9"))
                    .clipShape(RoundedRectangle(cornerRadius: 25))
            }
            .padding(.top, Spacing.xs)
            
            Button("Not Now") { viewModel.continueLocally() }
                .frame(minHeight: 44)
                .padding(.top, 8)
            Spacer(minLength: 34)
        }
        .padding(.horizontal, Spacing.lg)
        .background(Color(hex: "#FCFCFF"))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: -4)
    }
    
}
