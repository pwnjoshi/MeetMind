import Foundation

/// Thread-safe mock implementation of RemindersSyncServiceProtocol for testing and previews
public final class MockRemindersSyncService: RemindersSyncServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    
    private var _authorizationStatus: RemindersAuthorizationStatus = .authorized
    public var authorizationStatus: RemindersAuthorizationStatus {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _authorizationStatus
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _authorizationStatus = newValue
        }
    }
    
    public var wasSyncDispatched: Bool = false
    public var lastSyncedListTitle: String? = nil
    
    /// Target reminder list title accessor for test compatibility
    public var targetReminderListName: String? {
        get { lastSyncedListTitle }
        set { lastSyncedListTitle = newValue }
    }
    
    public var dispatchedPayloads: [ActionItemPayload] = []
    
    /// Count of dispatched reminders for test compatibility
    public var dispatchedRemindersCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return dispatchedPayloads.count
    }
    
    public var shouldThrowError: Error? = nil
    
    public init() {}
    
    public func requestAuthorization() async throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _authorizationStatus == .authorized
    }
    
    public func simulateAuthorizationStatus(_ status: RemindersAuthorizationStatus) {
        lock.lock()
        _authorizationStatus = status
        lock.unlock()
    }
    
    public func syncActionItems(_ items: [ActionItem], toList title: String) async throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        if let error = shouldThrowError {
            throw error
        }
        
        wasSyncDispatched = true
        lastSyncedListTitle = title
        
        for item in items {
            let payload = ActionItemPayload(
                id: item.id,
                title: item.title,
                notes: item.taskDescription.isEmpty ? nil : item.taskDescription,
                dueDate: item.dueDate,
                priority: item.priority.sortOrder
            )
            dispatchedPayloads.removeAll { $0.id == item.id }
            dispatchedPayloads.append(payload)
        }
        
        return items.map { $0.id.uuidString }
    }
}
