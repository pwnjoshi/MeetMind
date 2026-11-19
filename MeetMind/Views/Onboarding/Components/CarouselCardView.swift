import SwiftUI

/// Slide card display for Onboarding Welcome Carousel
public struct CarouselCardView: View {
    public let slide: OnboardingSlide
    
    public init(slide: OnboardingSlide) {
        self.slide = slide
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 50)
            ZStack {
                Circle().fill(Color(hex: "#EDEDFE")).frame(width: 310, height: 310)
                Circle().stroke(Color(hex: "#DDDDFC"), lineWidth: 1).frame(width: 370, height: 370)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.white)
                    .frame(width: 184, height: 150)
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                Image(systemName: slide.imageName)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Color(hex: "#4B3FF0"))
            }
            .accessibilityHidden(true)
            .padding(.bottom, 64)
            Text(slide.title)
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(slide.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
