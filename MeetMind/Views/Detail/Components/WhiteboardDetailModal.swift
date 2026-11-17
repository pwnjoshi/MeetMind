import SwiftUI

/// Full-screen zoom viewer for whiteboard and presentation slide captures
public struct WhiteboardDetailModal: View {
    public let photoPath: String
    public let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    
    public init(photoPath: String, onDismiss: @escaping () -> Void) {
        self.photoPath = photoPath
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: Spacing.lg) {
                    if let image = UIImage(contentsOfFile: photoPath) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("Meeting photo")
                    } else {
                        Text("This photo is no longer available.").foregroundStyle(.white)
                    }
                }
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale = max(0.8, min(3.0, $0)) }
                        .onEnded { _ in withAnimation { scale = 1.0 } }
                )
            }
            .navigationTitle("Whiteboard Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss).foregroundStyle(.white)
                }
            }
        }
    }
}
