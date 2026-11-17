import SwiftUI

/// Stage coordinator hosting welcome carousel, profile setup, and permissions primer
public struct OnboardingContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: OnboardingViewModel
    
    public init(permissionsService: PermissionsServiceProtocol = SystemPermissionsService()) {
        _viewModel = State(initialValue: OnboardingViewModel(permissionsService: permissionsService))
    }
    
    public var body: some View {
        Group {
            switch viewModel.currentStage {
            case .carousel:
                WelcomeAndSignInView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .verifyEmail:
                VerifyEmailView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .profileSetup:
                ProfileSetupView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .permissionsPrimer:
                PermissionsPrimerView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.currentStage)
        .onAppear {
            viewModel.onCompletion = { _ in
                appState.completeOnboarding()
            }
        }
        .onChange(of: viewModel.isOnboardingCompleted) { _, completed in
            if completed {
                appState.completeOnboarding()
            }
        }
    }
}

#Preview {
    OnboardingContainerView(permissionsService: MockPermissionsService())
        .environment(AppState())
}
