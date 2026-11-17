import Foundation

/// Supported system permission categories
public enum PermissionType: String, CaseIterable, Sendable, Codable {
    case microphone
    case speechRecognition
    case calendar
    case reminders
    case notifications
}

/// Authorization status state
public enum PermissionStatus: String, CaseIterable, Sendable, Codable {
    case notDetermined
    case authorized
    case denied
    case restricted
    
    public var isGranted: Bool {
        self == .authorized
    }
}

/// Protocol defining permission discovery and requesting
public protocol PermissionsServiceProtocol: AnyObject, Sendable {
    func status(for permission: PermissionType) -> PermissionStatus
    func requestPermission(for permission: PermissionType) async -> PermissionStatus
    func requestAllPermissions() async -> [PermissionType: PermissionStatus]
    var settingsURL: URL? { get }
}
