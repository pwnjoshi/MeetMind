import Foundation

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
