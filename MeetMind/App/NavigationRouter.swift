import Foundation
import SwiftUI
import Observation

/// State restoration snapshot capturing navigation hierarchy across app lifecycle
public struct NavigationRestorationSnapshot: Sendable, Codable, Equatable {
    public let selectedTabIndex: Int
    public let presentedMeetingDetailID: UUID?
    public let hasCompletedOnboarding: Bool
    
    public init(selectedTabIndex: Int, presentedMeetingDetailID: UUID?, hasCompletedOnboarding: Bool) {
        self.selectedTabIndex = selectedTabIndex
        self.presentedMeetingDetailID = presentedMeetingDetailID
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

/// Coordinator managing tab navigation paths, modal presentation, and deep links
@Observable
@MainActor
public final class NavigationRouter {
    public var homePath: [NavigationDestination] = []
    public var actionItemsPath: [NavigationDestination] = []
    public var searchPath: [NavigationDestination] = []
    public var settingsPath: [NavigationDestination] = []
    
    public var presentedMeetingDetailID: UUID? {
        get {
            for destination in homePath.reversed() {
                if case .meetingDetail(let id) = destination {
                    return id
                }
            }
            return nil
        }
        set {
            if let newValue {
                homePath.append(.meetingDetail(id: newValue))
            }
        }
    }
    
    public init() {}
    
    public func push(_ destination: NavigationDestination, on tab: TabIdentifier) {
        switch tab {
        case .home:
            homePath.append(destination)
        case .actionItems:
            actionItemsPath.append(destination)
        case .search:
            searchPath.append(destination)
        case .settings:
            settingsPath.append(destination)
        }
    }
    
    public func navigate(to destination: NavigationDestination, in tab: TabIdentifier = .home) {
        push(destination, on: tab)
    }
    
    public func pop(from tab: TabIdentifier) {
        switch tab {
        case .home:
            if !homePath.isEmpty { homePath.removeLast() }
        case .actionItems:
            if !actionItemsPath.isEmpty { actionItemsPath.removeLast() }
        case .search:
            if !searchPath.isEmpty { searchPath.removeLast() }
        case .settings:
            if !settingsPath.isEmpty { settingsPath.removeLast() }
        }
    }
    
    public func popToRoot(on tab: TabIdentifier) {
        switch tab {
        case .home:
            homePath.removeAll()
        case .actionItems:
            actionItemsPath.removeAll()
        case .search:
            searchPath.removeAll()
        case .settings:
            settingsPath.removeAll()
        }
    }
    
    public func handleDeepLink(url: URL, appState: AppState) -> Bool {
        guard url.scheme == "meetmind" else { return false }
        
        if url.host == "meeting" {
            let pathComponent = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let uuid = UUID(uuidString: pathComponent) else { return false }
            
            appState.activeTab = .home
            presentedMeetingDetailID = uuid
            return true
        } else if url.host == "tab" {
            let tabName = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let targetTab = TabIdentifier(rawValue: tabName) {
                appState.activeTab = targetTab
                return true
            }
        }
        return false
    }
    
    public func createRestorationSnapshot(appState: AppState) -> NavigationRestorationSnapshot {
        let tabIndex: Int
        switch appState.activeTab {
        case .home: tabIndex = 0
        case .actionItems: tabIndex = 1
        case .search: tabIndex = 2
        case .settings: tabIndex = 3
        }
        return NavigationRestorationSnapshot(
            selectedTabIndex: tabIndex,
            presentedMeetingDetailID: presentedMeetingDetailID,
            hasCompletedOnboarding: appState.hasCompletedOnboarding
        )
    }
    
    public func restore(from snapshot: NavigationRestorationSnapshot, appState: AppState) {
        switch snapshot.selectedTabIndex {
        case 0: appState.activeTab = .home
        case 1: appState.activeTab = .actionItems
        case 2: appState.activeTab = .search
        case 3: appState.activeTab = .settings
        default: appState.activeTab = .home
        }
        appState.hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        if let detailID = snapshot.presentedMeetingDetailID {
            presentedMeetingDetailID = detailID
        } else {
            homePath.removeAll()
        }
    }
}
