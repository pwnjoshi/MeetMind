import Foundation
import SwiftData

/// Keeps a repeating meeting tidy when it is edited after it was first scheduled.
@MainActor
enum MeetingRepeatEditing {
    /// When the time or the repeat rule of a repeating meeting changes, the occurrence generated for the
    /// old schedule would stay behind next to the new one. This removes that occurrence, but only while
    /// nobody has touched it: same title and agenda, still scheduled, no recording, no actions,
    /// no calendar event. Returns true when an occurrence was removed.
    @discardableResult
    static func removeStaleOccurrence(
        of meeting: Meeting,
        oldStart: Date,
        oldTitle: String,
        oldAgenda: String?,
        oldSeriesID: UUID?,
        oldRecurrence: MeetingRecurrence?,
        newStart: Date,
        newRecurrence: MeetingRecurrence?,
        context: ModelContext,
        store: MeetingPrepStore
    ) -> Bool {
        guard let oldRecurrence, let oldSeriesID else { return false }
        guard newStart != oldStart || newRecurrence != oldRecurrence else { return false }
        guard let all = try? context.fetch(FetchDescriptor<Meeting>()) else { return false }
        let plannedAgenda = PlannedAgenda.normalized(oldAgenda ?? "")

        let stale = all.filter { candidate in
            guard candidate.id != meeting.id, candidate.seriesID == oldSeriesID, candidate.status == .scheduled else { return false }
            guard (candidate.scheduledStartTime ?? candidate.createdAt) > oldStart else { return false }
            let record = store.record(for: candidate.id)
            guard record.recurrence == oldRecurrence, record.calendarEventID == nil else { return false }
            guard candidate.title == oldTitle, candidate.audioFileURL == nil,
                  candidate.transcriptSegments.isEmpty, candidate.actionItems.isEmpty else { return false }
            return PlannedAgenda.normalized(candidate.agendaText ?? "") == plannedAgenda
        }
        guard let next = stale.min(by: {
            ($0.scheduledStartTime ?? $0.createdAt) < ($1.scheduledStartTime ?? $1.createdAt)
        }) else { return false }

        store.remove(next.id)
        context.delete(next)
        try? context.save()
        return true
    }
}
