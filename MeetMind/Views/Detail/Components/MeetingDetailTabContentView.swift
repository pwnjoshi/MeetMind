import SwiftUI

/// Content router rendering the active tab in meeting detail cockpit
public struct MeetingDetailTabContentView: View {
    public let selectedTab: MeetingDetailTab
    public let summary: Summary?
    public let transcriptSegments: [TranscriptSegment]
    public let activeSegmentId: UUID?
    @Binding public var transcriptSearch: String
    public let actionItems: [ActionItem]
    public let notes: [Note]
    public let onSeekTranscript: (TranscriptSegment) -> Void
    public let onEditTranscript: (TranscriptSegment) -> Void
    public let onReassignSpeaker: (TranscriptSegment) -> Void
    public let onToggleAction: (ActionItem) -> Void
    public let onAddAction: () -> Void
    public let onSyncReminders: () -> Void
    public let onAddNote: () -> Void
    public let onSelectPhoto: (String) -> Void
    
    public var body: some View {
        switch selectedTab {
        case .summary:
            MeetingSummaryTabView(
                summary: summary,
                actionItems: actionItems)
        case .transcript:
            MeetingTranscriptTabView(
                segments: transcriptSegments,
                activeSegmentId: activeSegmentId,
                searchText: $transcriptSearch,
                onSeek: onSeekTranscript,
                onEdit: onEditTranscript,
                onReassign: onReassignSpeaker
            )
        case .actionItems:
            MeetingActionItemsTabView(
                items: actionItems,
                onToggle: onToggleAction,
                onAdd: onAddAction,
                onSyncReminders: onSyncReminders
            )
        case .notesMedia:
            MeetingNotesMediaTabView(
                notes: notes,
                onAddNote: onAddNote,
                onSelectPhoto: onSelectPhoto
            )
        }
    }
}
