import SwiftUI

/// What the transcript shows when there are no lines to list.
public enum TranscriptEmptyKind: Equatable, Sendable {
    case notAvailable
    case processing
}

/// Transcript grouped into speaker turns with search, highlighting of the line being played and auto-scroll.
public struct MeetingTranscriptTabView: View {
    public let segments: [TranscriptSegment]
    public let activeSegmentId: UUID?
    public let emptyKind: TranscriptEmptyKind
    @Binding public var searchText: String
    public let onSeek: (TranscriptSegment) -> Void
    public let onEdit: (TranscriptSegment) -> Void
    public let onReassign: (TranscriptSegment) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        segments: [TranscriptSegment],
        activeSegmentId: UUID?,
        searchText: Binding<String>,
        emptyKind: TranscriptEmptyKind = .notAvailable,
        onSeek: @escaping (TranscriptSegment) -> Void,
        onEdit: @escaping (TranscriptSegment) -> Void,
        onReassign: @escaping (TranscriptSegment) -> Void
    ) {
        self.segments = segments
        self.activeSegmentId = activeSegmentId
        self.emptyKind = emptyKind
        self._searchText = searchText
        self.onSeek = onSeek
        self.onEdit = onEdit
        self.onReassign = onReassign
    }

    private var isSearching: Bool { TranscriptSearch.isActive(searchText) }

    private var turns: [TranscriptTurn] {
        TranscriptTurnGrouper.turns(from: segments, matching: searchText)
    }

    public var body: some View {
        VStack(spacing: 8) {
            if !segments.isEmpty { searchField }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let shown = turns
        if segments.isEmpty {
            emptyState
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            turnList(shown)
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search transcript", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if isSearching {
                let count = TranscriptSearch.matchingLineCount(in: segments, query: searchText)
                Text(count == 1 ? "1 matching line" : "\(count) matching lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch emptyKind {
        case .processing:
            ContentUnavailableView(
                "Transcript Is Being Prepared",
                systemImage: "waveform",
                description: Text("The transcript appears here when on-device processing finishes. You can leave and come back.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notAvailable:
            ContentUnavailableView(
                "Transcript Not Available",
                systemImage: "doc.text.magnifyingglass",
                description: Text("A saved transcript will appear here after processing.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func turnList(_ shown: [TranscriptTurn]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(shown) { turn in
                        TranscriptTurnView(
                            turn: turn,
                            activeSegmentId: activeSegmentId,
                            query: searchText,
                            onSeek: onSeek,
                            onEdit: onEdit,
                            onReassign: onReassign
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: activeSegmentId) { _, newId in
                guard let newId, !isSearching else { return }
                if reduceMotion {
                    proxy.scrollTo(newId, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(newId, anchor: .center) }
                }
            }
        }
    }
}

/// A speaker turn: colour avatar, speaker name and start time, then the spoken lines.
struct TranscriptTurnView: View {
    let turn: TranscriptTurn
    let activeSegmentId: UUID?
    let query: String
    let onSeek: (TranscriptSegment) -> Void
    let onEdit: (TranscriptSegment) -> Void
    let onReassign: (TranscriptSegment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(turn.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color(hex: turn.colorHex), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                header
                ForEach(turn.segments) { segment in
                    TranscriptSegmentRowView(
                        segment: segment,
                        isActive: segment.id == activeSegmentId,
                        query: query,
                        onSeek: { onSeek(segment) },
                        onEdit: { onEdit(segment) },
                        onReassignSpeaker: { onReassign(segment) }
                    )
                    .id(segment.id)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(turn.speakerName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(turn.timestampText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
    }
}
