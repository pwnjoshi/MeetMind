import SwiftUI

/// Paged horizontal TabView with animated capsule indicators and hero illustrations
public struct OnboardingWelcomeView: View {
    @Bindable public var viewModel: OnboardingViewModel
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                GhostButton(title: "Skip") {
                    viewModel.skipCarousel()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            
            TabView(selection: $viewModel.currentSlideIndex) {
                ForEach(viewModel.slides) { slide in
                    CarouselCardView(slide: slide)
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            VStack(spacing: Spacing.xl) {
                CarouselIndicatorView(
                    totalCount: viewModel.totalSlides,
                    currentIndex: viewModel.currentSlideIndex
                )
                bottomActionBar
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
    
    @ViewBuilder
    private var bottomActionBar: some View {
        if viewModel.currentSlideIndex == viewModel.totalSlides - 1 {
            PrimaryButton(title: "Get Started", icon: "arrow.right") {
                viewModel.advanceSlide()
            }
        } else {
            HStack(spacing: Spacing.md) {
                if viewModel.currentSlideIndex > 0 {
                    GhostButton(title: "Back") {
                        viewModel.regressSlide()
                    }
                    .frame(maxWidth: 100)
                }
                
                PrimaryButton(title: "Continue", icon: "chevron.right") {
                    viewModel.advanceSlide()
                }
            }
        }
    }
}
