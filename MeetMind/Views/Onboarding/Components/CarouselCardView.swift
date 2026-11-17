import SwiftUI

/// Slide card display for Onboarding Welcome Carousel
public struct CarouselCardView: View {
    public let slide: OnboardingSlide
    
    public init(slide: OnboardingSlide) {
        self.slide = slide
    }
    
    public var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Theme.Colors.primarySlate.opacity(0.08))
                    .frame(width: 160, height: 160)
                
                Image(systemName: slide.imageName)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primarySlate)
            }
            .accessibilityHidden(true)
            
            VStack(spacing: Spacing.md) {
                Text(slide.title)
                    .font(Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(slide.subtitle)
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.lg)
            }
            
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
    }
}
