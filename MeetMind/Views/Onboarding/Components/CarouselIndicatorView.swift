import SwiftUI

/// Animated horizontal capsule page indicator
public struct CarouselIndicatorView: View {
    public let totalCount: Int
    public let currentIndex: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(totalCount: Int, currentIndex: Int) {
        self.totalCount = totalCount
        self.currentIndex = currentIndex
    }
    
    public var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color(hex: "#4B3FF0") : Color(uiColor: .systemGray4))
                    .frame(width: index == currentIndex ? 20 : 8, height: 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentIndex)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentIndex + 1) of \(totalCount)")
    }
}
