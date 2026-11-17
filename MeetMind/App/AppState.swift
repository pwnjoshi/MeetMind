import Foundation
import SwiftUI
import Observation

/// Global application-level sheet presentations
public enum AppSheet: Identifiable, Sendable {
    case newMeeting
    case scheduleMeeting
    case audioImport
    case editActionItem(id: UUID)
    case exportMinutes(meetingId: UUID)
    case askAIAssistant(meetingId: UUID)
    
    public var id: String {
        switch self {
        case .newMeeting:
            return "newMeeting"
        case .scheduleMeeting:
            return "scheduleMeeting"
        case .audioImport:
            return "audioImport"
        case .editActionItem(let id):
            return "editActionItem_\(id.uuidString)"
        case .exportMinutes(let id):
            return "exportMinutes_\(id.uuidString)"
        case .askAIAssistant(let id):
            return "askAI_\(id.uuidString)"
        }
    }
}

/// Global application-level alert presentations
public enum AppAlert: Identifiable, Sendable {
    case permissionDenied(permission: String, message: String)
    case genericError(title: String, message: String)
    case confirmDiscardRecording
    
    public var id: String {
        switch self {
        case .permissionDenied(let p, _):
            return "permission_\(p)"
        case .genericError(let t, _):
            return "error_\(t)"
        case .confirmDiscardRecording:
            return "confirmDiscard"
        }
    }
}

/// Central application state manager
@Observable
@MainActor
public final class AppState {
    private let userDefaults: UserDefaults
    
    public var hasCompletedOnboarding: Bool {
        didSet {
            userDefaults.set(hasCompletedOnboarding, forKey: "MeetMind_IsOnboardingCompleted")
        }
    }
    
    public var activeTab: TabIdentifier = .home
    public var actionItemsBadgeCount: Int = 0
    public var isRecordingActive: Bool = false
    public var currentRecordingMeetingId: UUID? = nil
    
    public var activeSheet: AppSheet? = nil
    public var activeAlert: AppAlert? = nil
    
    public var onScrollToTopRequested: (() -> Void)? = nil
    
    public var formattedActionItemsBadge: String? {
        if actionItemsBadgeCount <= 0 {
            return nil
        } else if actionItemsBadgeCount > 99 {
            return "99+"
        } else {
            return "\(actionItemsBadgeCount)"
        }
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.hasCompletedOnboarding = userDefaults.bool(forKey: "MeetMind_IsOnboardingCompleted")
    }
    
    public func completeOnboarding() {
        hasCompletedOnboarding = true
        activeTab = .home
    }
    
    public func resetOnboarding() {
        hasCompletedOnboarding = false
        activeTab = .home
    }
    
    public func handleTabReselection(tab: TabIdentifier) {
        if activeTab == tab {
            onScrollToTopRequested?()
        }
    }
    
    public func updateBadgeCount(_ count: Int) {
        actionItemsBadgeCount = max(0, count)
    }
    
    public func presentSheet(_ sheet: AppSheet) {
        activeSheet = sheet
    }
    
    public func dismissSheet() {
        activeSheet = nil
    }
    
    public func showAlert(_ alert: AppAlert) {
        activeAlert = alert
    }
    
    public func dismissAlert() {
        activeAlert = nil
    }
}
