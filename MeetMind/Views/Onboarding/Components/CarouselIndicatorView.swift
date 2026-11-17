import SwiftUI

/// Animated horizontal capsule page indicator
public struct CarouselIndicatorView: View {
    public let totalCount: Int
    public let currentIndex: Int
    
    public init(totalCount: Int, currentIndex: Int) {
        self.totalCount = totalCount
        self.currentIndex = currentIndex
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Theme.Colors.primarySlate : Theme.Colors.cardBorder)
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(totalCount)")
    }
}
