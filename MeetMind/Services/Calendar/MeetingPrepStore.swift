import Foundation
import SwiftData

/// Preparation data that has no SwiftData field: recurrence, coordinator and the linked calendar event.
public struct MeetingPrepRecord: Codable, Equatable, Sendable {
    public var recurrence: MeetingRecurrence?
    public var coordinatorID: UUID?
    public var calendarEventID: String?

    public init(recurrence: MeetingRecurrence? = nil, coordinatorID: UUID? = nil, calendarEventID: String? = nil) {
        self.recurrence = recurrence
        self.coordinatorID = coordinatorID
        self.calendarEventID = calendarEventID
    }

    var isEmpty: Bool { recurrence == nil && coordinatorID == nil && calendarEventID == nil }
}

/// Small on-device JSON store (UserDefaults) keyed by meeting UUID.
@MainActor
public final class MeetingPrepStore {
    public static let shared = MeetingPrepStore()

    private let defaults: UserDefaults
    private let key: String
    private var cache: [String: MeetingPrepRecord]
    private var loadFailure: String?

    public init(defaults: UserDefaults = .standard, key: String = "manent.meetingPrep.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key) {
            do { self.cache = try JSONDecoder().decode([String: MeetingPrepRecord].self, from: data) }
            catch {
                self.cache = [:]
                self.loadFailure = error.localizedDescription
            }
        } else {
            self.cache = [:]
        }
    }

    public func record(for meetingID: UUID) -> MeetingPrepRecord {
        cache[meetingID.uuidString] ?? MeetingPrepRecord()
    }

    public func recurrence(for meetingID: UUID) -> MeetingRecurrence? {
        record(for: meetingID).recurrence
    }

    public func coordinatorID(for meetingID: UUID) -> UUID? {
        record(for: meetingID).coordinatorID
    }

    public func update(_ meetingID: UUID, _ change: (inout MeetingPrepRecord) -> Void) {
        var current = record(for: meetingID)
        change(&current)
        if current.isEmpty {
            cache.removeValue(forKey: meetingID.uuidString)
        } else {
            cache[meetingID.uuidString] = current
        }
        persist()
    }

    public func remove(_ meetingID: UUID) {
        try? remove(meetingID: meetingID)
    }

    public func remove(meetingID: UUID) throws {
        if loadFailure != nil { throw SidecarStoreError.corrupt("Meeting preparation") }
        cache.removeValue(forKey: meetingID.uuidString)
        persist()
    }

    public func eraseAll() {
        cache.removeAll()
        loadFailure = nil
        defaults.removeObject(forKey: key)
    }

    public var isEmpty: Bool { cache.isEmpty }

    /// Meeting ids that currently repeat.
    public var repeatingMeetingIDs: [UUID] {
        cache.compactMap { entry in
            entry.value.recurrence == nil ? nil : UUID(uuidString: entry.key)
        }
    }

    /// "Repeats weekly" style text for Home and detail rows; nil when the meeting does not repeat.
    public func repeatSummary(for meetingID: UUID) -> String? {
        recurrence(for: meetingID)?.summaryText
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Creates the next scheduled occurrence of a repeating meeting.
@MainActor
public enum MeetingOccurrenceScheduler {
    /// Inserts the next occurrence (or returns the one already scheduled for that slot).
    @discardableResult
    public static func scheduleNext(
        after meeting: Meeting,
        recurrence: MeetingRecurrence,
        now: Date = Date(),
        context: ModelContext,
        store: MeetingPrepStore = .shared,
        calendar: Calendar = .current
    ) throws -> Meeting {
        let base = meeting.scheduledStartTime ?? meeting.createdAt
        let nextStart = recurrence.nextOccurrence(after: base, now: now, calendar: calendar)

        let hadSeries = meeting.seriesID != nil
        let previousName = meeting.seriesName
        let seriesID = meeting.seriesID ?? UUID()
        if !hadSeries {
            meeting.seriesID = seriesID
            meeting.seriesName = meeting.title
        }

        let all = try context.fetch(FetchDescriptor<Meeting>())
        if let existing = all.first(where: { $0.seriesID == seriesID && $0.scheduledStartTime == nextStart && $0.id != meeting.id }) {
            return existing
        }

        let occurrence = Meeting(
            title: meeting.title,
            createdAt: now,
            scheduledStartTime: nextStart,
            duration: meeting.duration,
            status: .scheduled,
            audioQuality: meeting.audioQuality,
            templateName: meeting.templateName,
            folder: meeting.folder
        )
        occurrence.seriesID = seriesID
        occurrence.seriesName = meeting.seriesName ?? meeting.title
        occurrence.agendaText = PlannedAgenda.planned(meeting) // never the previous meeting's derived topics
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
        let coordinator = store.coordinatorID(for: meeting.id)
        store.update(occurrence.id) {
            $0.recurrence = recurrence
            $0.coordinatorID = coordinator
        }
        return occurrence
    }

    /// Generates the next occurrence for every repeating meeting whose slot has started.
    /// Safe to call repeatedly; call it on launch or when a meeting finishes.
    @discardableResult
    public static func generateDueOccurrences(
        now: Date = Date(),
        context: ModelContext,
        store: MeetingPrepStore = .shared
    ) throws -> [Meeting] {
        let ids = Set(store.repeatingMeetingIDs)
        guard !ids.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<Meeting>())
        var created: [Meeting] = []
        for meeting in all where ids.contains(meeting.id) {
            let start = meeting.scheduledStartTime ?? meeting.createdAt
            guard start <= now, let recurrence = store.recurrence(for: meeting.id) else { continue }
            let next = try scheduleNext(after: meeting, recurrence: recurrence, now: now, context: context, store: store)
            if !all.contains(where: { $0.id == next.id }) {
                created.append(next)
            }
        }
        return created
    }
}
