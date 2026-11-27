import SwiftUI

/// One spoken line inside a speaker turn. The line being played is highlighted, a tap seeks and plays
/// from it, and the context menu edits the text or reassigns the speaker.
public struct TranscriptSegmentRowView: View {
    public let segment: TranscriptSegment
    public let isActive: Bool
    public let query: String
    public let onSeek: () -> Void
    public let onEdit: () -> Void
    public let onReassignSpeaker: () -> Void

    public init(
        segment: TranscriptSegment,
        isActive: Bool,
        query: String = "",
        onSeek: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onReassignSpeaker: @escaping () -> Void
    ) {
        self.segment = segment
        self.isActive = isActive
        self.query = query
        self.onSeek = onSeek
        self.onEdit = onEdit
        self.onReassignSpeaker = onReassignSpeaker
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(segment.formattedStartTime)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isActive ? Theme.Colors.manentAccent : Color.secondary)
                .frame(width: 42, alignment: .leading)
            Text(TranscriptSearch.highlighted(segment.text, query: query))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(highlightShape)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSeek)
        .contextMenu {
            Button("Play from Here", systemImage: "play.fill", action: onSeek)
            Button("Edit Text", systemImage: "pencil", action: onEdit)
            Button("Reassign Speaker", systemImage: "person.crop.circle.badge.questionmark", action: onReassignSpeaker)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays the recording from this line")
        .accessibilityValue(isActive ? "Playing" : "")
    }

    private var highlightShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? Theme.Colors.manentAccent.opacity(0.14) : Color.clear)
    }
}
