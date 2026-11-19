import SwiftUI

/// Paged horizontal TabView with animated capsule indicators and hero illustrations
public struct OnboardingWelcomeView: View {
    @Bindable public var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    viewModel.skipCarousel()
                }
                .frame(minWidth: 44, minHeight: 44)
                .opacity(viewModel.currentSlideIndex == viewModel.totalSlides - 1 ? 0 : 1)
                .disabled(viewModel.currentSlideIndex == viewModel.totalSlides - 1)
                .accessibilityHidden(viewModel.currentSlideIndex == viewModel.totalSlides - 1)
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
        .background(LinearGradient(colors: [Color(hex: "#F0F0FF"), .white], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .tint(Color(hex: "#4B3FF0"))
        .environment(\.colorScheme, .light)
    }
    
    private var bottomActionBar: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                viewModel.advanceSlide()
            }
        } label: {
            Text(viewModel.currentSlideIndex == viewModel.totalSlides - 1 ? "Get Started" : "Continue")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(hex: "#4B3FF0"), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
