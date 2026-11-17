import SwiftUI

/// Transcript tab containing diarized dialogue feed, playback sync, and search filter
public struct MeetingTranscriptTabView: View {
    public let segments: [TranscriptSegment]
    public let activeSegmentId: UUID?
    @Binding public var searchText: String
    public let onSeek: (TranscriptSegment) -> Void
    public let onEdit: (TranscriptSegment) -> Void
    public let onReassign: (TranscriptSegment) -> Void
    
    public init(
        segments: [TranscriptSegment],
        activeSegmentId: UUID?,
        searchText: Binding<String>,
        onSeek: @escaping (TranscriptSegment) -> Void,
        onEdit: @escaping (TranscriptSegment) -> Void,
        onReassign: @escaping (TranscriptSegment) -> Void
    ) {
        self.segments = segments
        self.activeSegmentId = activeSegmentId
        self._searchText = searchText
        self.onSeek = onSeek
        self.onEdit = onEdit
        self.onReassign = onReassign
    }
    
    private var displayedSegments: [TranscriptSegment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return segments }
        return segments.filter { $0.text.lowercased().contains(query) }
    }
    
    public var body: some View {
        VStack(spacing: Spacing.sm) {
            SearchBar(text: $searchText, placeholder: "Filter spoken dialogue...")
                .padding(.horizontal, Spacing.lg)
            
            if displayedSegments.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No matching transcript segments").font(Typography.body)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(displayedSegments) { seg in
                                TranscriptSegmentRowView(
                                    segment: seg,
                                    isActive: seg.id == activeSegmentId,
                                    onSeek: { onSeek(seg) },
                                    onEdit: { onEdit(seg) },
                                    onReassignSpeaker: { onReassign(seg) }
                                )
                                .id(seg.id)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                    }
                    .onChange(of: activeSegmentId) { _, newId in
                        if let newId { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(newId, anchor: .center) } }
                    }
                }
            }
        }
    }
}
