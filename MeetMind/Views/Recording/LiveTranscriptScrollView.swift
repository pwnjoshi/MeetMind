import SwiftUI

/// Auto-scrolling transcript feed with manual scroll override floating pill
public struct LiveTranscriptScrollView: View {
    public let segments: [LiveTranscriptSegmentItem]
    public let interimText: String
    
    @State private var isAutoScrollActive: Bool = true
    
    public init(segments: [LiveTranscriptSegmentItem], interimText: String = "") {
        self.segments = segments
        self.interimText = interimText
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(segments) { segment in
                            LiveTranscriptBubbleView(segment: segment)
                                .id(segment.id)
                        }
                        
                        if !interimText.isEmpty {
                            LiveInterimTranscriptBubbleView(text: interimText)
                                .id("interim_bubble_id")
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .id("bottom_anchor_id")
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        if isAutoScrollActive { isAutoScrollActive = false }
                    }
                )
                
                if !isAutoScrollActive {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isAutoScrollActive = true
                            proxy.scrollTo("bottom_anchor_id", anchor: .bottom)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                            Text("Resume Auto-Scroll")
                        }
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.liveBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .contentShape(Capsule())
                    }
                    .padding(.bottom, Spacing.sm)
                }
            }
            .onChange(of: segments.count) { _, _ in
                if isAutoScrollActive {
                    withAnimation { proxy.scrollTo("bottom_anchor_id", anchor: .bottom) }
                }
            }
            .onChange(of: interimText) { _, _ in
                if isAutoScrollActive {
                    withAnimation { proxy.scrollTo("bottom_anchor_id", anchor: .bottom) }
                }
            }
        }
    }
}
