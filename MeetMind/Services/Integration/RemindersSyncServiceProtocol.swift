import Foundation
import EventKit

/// Authorization status for Apple Reminders EventKit integration
public enum RemindersAuthorizationStatus: String, Codable, Sendable {
    case notDetermined = "notDetermined"
    case authorized = "authorized"
    case denied = "denied"
    case restricted = "restricted"
}

/// Normalized payload representation of an action item sent to Apple Reminders
public struct ActionItemPayload: Sendable, Equatable, Codable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let dueDate: Date?
    public let priority: Int
    
    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
    }
}

/// Protocol defining the contract for syncing action items to Apple Reminders via EventKit
public protocol RemindersSyncServiceProtocol: AnyObject, Sendable {
    /// Current authorization status of the user's Reminders store
    var authorizationStatus: RemindersAuthorizationStatus { get }
    
    /// Requests user authorization to access Apple Reminders
    func requestAuthorization() async throws -> Bool
    
    /// Synchronizes an array of ActionItem entities to a designated Reminders list
    func syncActionItems(_ items: [ActionItem], toList title: String) async throws -> [String]
}

public final class SystemRemindersSyncService: RemindersSyncServiceProtocol, @unchecked Sendable {
    private let store = EKEventStore()
    public init() {}

    public var authorizationStatus: RemindersAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized, .fullAccess: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func syncActionItems(_ items: [ActionItem], toList title: String) async throws -> [String] {
        guard try await requestAuthorization() else {
            throw NSError(domain: "MeetMind.Reminders", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Enable Reminders access for MeetMind in Settings to sync tasks."])
        }
        return try await MainActor.run {
            let calendar: EKCalendar
            if let existing = store.calendars(for: .reminder).first(where: {
                $0.title == title && $0.allowsContentModifications && $0.source?.sourceType == .local
            }) {
                calendar = existing
            } else {
                guard let source = store.sources.first(where: { $0.sourceType == .local }) else {
                    throw NSError(domain: "MeetMind.Reminders", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "No on-device Reminders account is available. Keep tasks in MeetMind or enable an On My iPhone Reminders account. Cloud lists are excluded to keep meeting content on this iPhone."])
                }
                calendar = EKCalendar(for: .reminder, eventStore: store)
                calendar.title = title
                calendar.source = source
                try store.saveCalendar(calendar, commit: true)
            }
            var identifiers: [String] = []
            for item in items {
                let existing = item.reminderIdentifier.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
                    .flatMap { $0.calendar?.source?.sourceType == .local ? $0 : nil }
                let reminder = existing ?? EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.title = item.title
                reminder.notes = item.taskDescription
                reminder.isCompleted = item.isCompleted
                reminder.priority = item.priorityRaw.isEmpty ? 0 : (item.priority == .urgent ? 1 : (item.priority == .high ? 3 : (item.priority == .medium ? 5 : 9)))
                reminder.dueDateComponents = item.dueDate.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
                try store.save(reminder, commit: true)
                item.reminderIdentifier = reminder.calendarItemIdentifier
                try item.modelContext?.save()
                identifiers.append(reminder.calendarItemIdentifier)
            }
            return identifiers
        }
    }
}
