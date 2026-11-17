import SwiftUI

/// Floating tool dock for bookmarks, live notes, and whiteboard photo snaps
public struct LiveActionToolDock: View {
    public let bookmarkCount: Int
    public let isBookmarkHighlighted: Bool
    public let notesCount: Int
    public let photosCount: Int
    public var onBookmarkTap: () -> Void
    public var onNoteTap: () -> Void
    public var onPhotoTap: () -> Void
    
    public init(
        bookmarkCount: Int,
        isBookmarkHighlighted: Bool,
        notesCount: Int,
        photosCount: Int,
        onBookmarkTap: @escaping () -> Void,
        onNoteTap: @escaping () -> Void,
        onPhotoTap: @escaping () -> Void
    ) {
        self.bookmarkCount = bookmarkCount
        self.isBookmarkHighlighted = isBookmarkHighlighted
        self.notesCount = notesCount
        self.photosCount = photosCount
        self.onBookmarkTap = onBookmarkTap
        self.onNoteTap = onNoteTap
        self.onPhotoTap = onPhotoTap
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            LiveBookmarkButton(
                count: bookmarkCount,
                isHighlighted: isBookmarkHighlighted,
                onAddBookmark: onBookmarkTap
            )
            
            dockButton(
                iconName: "square.and.pencil",
                label: "Notes",
                badgeCount: notesCount,
                action: onNoteTap
            )
            
            dockButton(
                iconName: "camera.fill",
                label: "Whiteboard",
                badgeCount: photosCount,
                action: onPhotoTap
            )
        }
    }
    
    private func dockButton(iconName: String, label: String, badgeCount: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.Colors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.Colors.cardBorder, lineWidth: 1))
                
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.liveBlue)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .accessibilityLabel("\(label) (\(badgeCount) items)")
    }
}
