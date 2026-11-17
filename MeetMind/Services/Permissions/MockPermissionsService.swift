import Foundation

/// Deterministic mock implementation of PermissionsServiceProtocol for tests and previews
public final class MockPermissionsService: PermissionsServiceProtocol, @unchecked Sendable {
    public var statuses: [PermissionType: PermissionStatus] = [:]
    public var requestedPermissions: [PermissionType] = []
    public var mockSettingsURL: URL? = URL(string: "app-settings:")
    
    public init(initialStatuses: [PermissionType: PermissionStatus] = [:]) {
        self.statuses = initialStatuses
    }
    
    public func status(for permission: PermissionType) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }
    
    public func requestPermission(for permission: PermissionType) async -> PermissionStatus {
        requestedPermissions.append(permission)
        let current = statuses[permission]
        let resolved = (current == nil || current == .notDetermined) ? .authorized : current!
        statuses[permission] = resolved
        return resolved
    }
    
    public func requestAllPermissions() async -> [PermissionType: PermissionStatus] {
        for type in PermissionType.allCases {
            if statuses[type] == nil || statuses[type] == .notDetermined {
                statuses[type] = .authorized
            }
            requestedPermissions.append(type)
        }
        return statuses
    }
    
    public var settingsURL: URL? {
        mockSettingsURL
    }
    
    public func setStatus(_ status: PermissionStatus, for permission: PermissionType) {
        statuses[permission] = status
    }
}
