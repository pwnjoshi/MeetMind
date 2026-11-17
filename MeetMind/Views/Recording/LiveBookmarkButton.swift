import SwiftUI

/// One-tap bookmark button with debounce, haptic feedback, and counter badge
public struct LiveBookmarkButton: View {
    public let count: Int
    public let isHighlighted: Bool
    public var onAddBookmark: () -> Void
    
    @State private var isAnimatingTap: Bool = false
    
    public init(
        count: Int,
        isHighlighted: Bool = false,
        onAddBookmark: @escaping () -> Void
    ) {
        self.count = count
        self.isHighlighted = isHighlighted
        self.onAddBookmark = onAddBookmark
    }
    
    public var body: some View {
        Button {
            triggerFeedback()
            onAddBookmark()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: isHighlighted ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Theme.Colors.warmAmber : Theme.Colors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(isHighlighted ? Theme.Colors.warmAmberLight : Theme.Colors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.Colors.cardBorder, lineWidth: 1))
                    .scaleEffect(isAnimatingTap ? 1.2 : 1.0)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.warmAmber)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel("Add Bookmark (\(count) bookmarks added)")
    }
    
    private func triggerFeedback() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            isAnimatingTap = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isAnimatingTap = false
        }
    }
}
