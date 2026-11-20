import Foundation
import SwiftData

/// Repeat choices shown on the Repeat sheet.
public enum MeetingRepeatOption: String, CaseIterable, Sendable, Identifiable {
    case never
    case everyWeek

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .never: return "Never"
        case .everyWeek: return "Every Week"
        }
    }
}

/// Schedules the next weekly occurrence of a meeting as a local scheduled meeting
/// that shares the original's series and participants.
@MainActor
public enum MeetingRepeatService {
    /// Text such as "Wednesday at 5:30 PM" for the meeting's weekly slot.
    public static func weeklySubtitle(for meeting: Meeting) -> String {
        let base = meeting.scheduledStartTime ?? meeting.createdAt
        let day = base.formatted(.dateTime.weekday(.wide))
        let time = base.formatted(date: .omitted, time: .shortened)
        return "\(day) at \(time)"
    }

    /// First weekly slot after `base` that is also later than `now`.
    public static func nextOccurrenceDate(after base: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        var next = calendar.date(byAdding: .weekOfYear, value: 1, to: base) ?? base.addingTimeInterval(604_800)
        var steps = 0
        while next <= now && steps < 1_040 {
            next = calendar.date(byAdding: .weekOfYear, value: 1, to: next) ?? next.addingTimeInterval(604_800)
            steps += 1
        }
        return next
    }

    /// Creates (or returns the already scheduled) next occurrence.
    @discardableResult
    public static func scheduleNextOccurrence(of meeting: Meeting, now: Date = Date(), context: ModelContext) throws -> Meeting {
        let base = meeting.scheduledStartTime ?? meeting.createdAt
        let next = nextOccurrenceDate(after: base, now: now)

        let hadSeries = meeting.seriesID != nil
        let previousName = meeting.seriesName
        let seriesID = meeting.seriesID ?? UUID()
        if !hadSeries {
            meeting.seriesID = seriesID
            meeting.seriesName = meeting.title
        }

        let all = try context.fetch(FetchDescriptor<Meeting>())
        if let existing = all.first(where: { $0.seriesID == seriesID && $0.scheduledStartTime == next && $0.id != meeting.id }) {
            return existing
        }

        let occurrence = Meeting(
            title: meeting.title,
            createdAt: now,
            scheduledStartTime: next,
            duration: meeting.duration,
            status: .scheduled,
            audioQuality: meeting.audioQuality,
            templateName: meeting.templateName,
            folder: meeting.folder
        )
        occurrence.seriesID = seriesID
        occurrence.seriesName = meeting.seriesName ?? meeting.title
        occurrence.agendaText = meeting.agendaText
        context.insert(occurrence)
        occurrence.participants = meeting.participants
        do {
            try context.save()
        } catch {
            context.delete(occurrence)
            if !hadSeries {
                meeting.seriesID = nil
                meeting.seriesName = previousName
            }
            throw error
        }
        return occurrence
    }
}
