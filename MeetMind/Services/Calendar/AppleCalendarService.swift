import Foundation
import EventKit

/// Calendar authorization as shown on the Apple Calendar screen.
public enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess

    public var isGranted: Bool { self == .fullAccess || self == .writeOnly }

    /// Trailing value of the "Calendar Access" row.
    public var label: String {
        switch self {
        case .notDetermined, .denied: return "Not Allowed"
        case .restricted: return "Restricted"
        case .writeOnly: return "Add Only"
        case .fullAccess: return "Allowed"
        }
    }
}

public enum CalendarServiceError: LocalizedError, Sendable {
    case notAuthorized
    case noWritableCalendar

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar access is not allowed."
        case .noWritableCalendar: return "No calendar is available for new events."
        }
    }
}

@MainActor
public protocol CalendarServicing: AnyObject {
    var access: CalendarAccess { get }
    /// True once the user tapped Connect Apple Calendar and access was granted.
    var isConnected: Bool { get }
    func requestFullAccess() async -> CalendarAccess
    /// Creates or updates the event for `meeting` and returns its identifier.
    func upsertEvent(for meeting: Meeting, existingIdentifier: String?) throws -> String
}

/// EventKit integration. Nothing is read or written until the user connects the calendar.
@MainActor
public final class AppleCalendarService: CalendarServicing {
    public static let shared = AppleCalendarService()

    private static let connectedKey = "manent.calendar.connected"
    private let defaults: UserDefaults
    private lazy var store = EKEventStore()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        default: return .denied
        }
    }

    public var isConnected: Bool {
        defaults.bool(forKey: Self.connectedKey) && access.isGranted
    }

    public func requestFullAccess() async -> CalendarAccess {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            // The resulting status below reflects the refusal.
        }
        let result = access
        defaults.set(result.isGranted, forKey: Self.connectedKey)
        return result
    }

    /// Turns the connection off inside Manent (system permission stays as is).
    public func disconnect() {
        defaults.set(false, forKey: Self.connectedKey)
    }

    public func upsertEvent(for meeting: Meeting, existingIdentifier: String?) throws -> String {
        guard access.isGranted else { throw CalendarServiceError.notAuthorized }
        let event: EKEvent
        if let existingIdentifier, access == .fullAccess, let found = store.event(withIdentifier: existingIdentifier) {
            event = found
        } else {
            event = EKEvent(eventStore: store)
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalendarServiceError.noWritableCalendar
            }
            event.calendar = calendar
        }
        let start = meeting.scheduledStartTime ?? meeting.createdAt
        event.title = meeting.title
        event.startDate = start
        event.endDate = start.addingTimeInterval(max(meeting.duration, 900))
        let agenda = meeting.agendaText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        event.notes = agenda.isEmpty ? nil : agenda
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier ?? ""
    }
}
