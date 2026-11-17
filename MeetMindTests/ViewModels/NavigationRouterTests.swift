//
//  NavigationRouterTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
@testable import MeetMind

/// Comprehensive unit test suite covering AppState and NavigationRouter:
/// Tab navigation paths, badge computation, tab reselection, deep linking, modal sheets, and state restoration.
final class NavigationRouterTests: XCTestCase {
    
    private var mockUserDefaults: UserDefaults!
    private var suiteName: String!
    private var appState: AppState!
    private var router: NavigationRouter!
    
    override func setUp() {
        super.setUp()
        suiteName = "NavigationRouterTests_\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: suiteName)
        appState = AppState(userDefaults: mockUserDefaults)
        router = NavigationRouter()
    }
    
    override func tearDown() {
        mockUserDefaults.removePersistentDomain(forName: suiteName)
        mockUserDefaults = nil
        appState = nil
        router = nil
        super.tearDown()
    }
    
    // MARK: - AppState Tests
    
    func test_initialAppState() {
        XCTAssertFalse(appState.hasCompletedOnboarding)
        XCTAssertEqual(appState.activeTab, .home)
        XCTAssertEqual(appState.actionItemsBadgeCount, 0)
        XCTAssertNil(appState.formattedActionItemsBadge)
        XCTAssertFalse(appState.isRecordingActive)
        XCTAssertNil(appState.currentRecordingMeetingId)
        XCTAssertNil(appState.activeSheet)
        XCTAssertNil(appState.activeAlert)
    }
    
    func test_completeAndResetOnboarding() {
        appState.completeOnboarding()
        XCTAssertTrue(appState.hasCompletedOnboarding)
        XCTAssertEqual(appState.activeTab, .home)
        
        appState.resetOnboarding()
        XCTAssertFalse(appState.hasCompletedOnboarding)
    }
    
    func test_badgeFormatting() {
        appState.updateBadgeCount(0)
        XCTAssertNil(appState.formattedActionItemsBadge)
        
        appState.updateBadgeCount(5)
        XCTAssertEqual(appState.formattedActionItemsBadge, "5")
        
        appState.updateBadgeCount(99)
        XCTAssertEqual(appState.formattedActionItemsBadge, "99")
        
        appState.updateBadgeCount(150)
        XCTAssertEqual(appState.formattedActionItemsBadge, "99+")
        
        appState.updateBadgeCount(-10)
        XCTAssertNil(appState.formattedActionItemsBadge)
    }
    
    func test_tabReselectionTriggersScrollToTop() {
        var didScrollToTop = false
        appState.onScrollToTopRequested = {
            didScrollToTop = true
        }
        
        appState.activeTab = .home
        appState.handleTabReselection(tab: .home)
        XCTAssertTrue(didScrollToTop)
        
        didScrollToTop = false
        appState.handleTabReselection(tab: .settings)
        XCTAssertFalse(didScrollToTop)
    }
    
    func test_sheetAndAlertPresentation() {
        appState.presentSheet(.newMeeting)
        XCTAssertEqual(appState.activeSheet?.id, "newMeeting")
        
        appState.dismissSheet()
        XCTAssertNil(appState.activeSheet)
        
        appState.showAlert(.confirmDiscardRecording)
        XCTAssertEqual(appState.activeAlert?.id, "confirmDiscard")
        
        appState.dismissAlert()
        XCTAssertNil(appState.activeAlert)
    }
    
    // MARK: - NavigationRouter Tests
    
    func test_perTabPathSeparation() {
        let meetingID = UUID()
        router.push(.meetingDetail(id: meetingID), on: .home)
        
        XCTAssertEqual(router.homePath.count, 1)
        XCTAssertEqual(router.actionItemsPath.count, 0)
        XCTAssertEqual(router.searchPath.count, 0)
        XCTAssertEqual(router.settingsPath.count, 0)
        
        router.push(.settings, on: .settings)
        XCTAssertEqual(router.settingsPath.count, 1)
        XCTAssertEqual(router.homePath.count, 1)
        
        router.pop(from: .home)
        XCTAssertEqual(router.homePath.count, 0)
        XCTAssertEqual(router.settingsPath.count, 1)
        
        router.popToRoot(on: .settings)
        XCTAssertEqual(router.settingsPath.count, 0)
    }
    
    func test_navigateConvenienceMethod() {
        let meetingID = UUID()
        router.navigate(to: .meetingDetail(id: meetingID), in: .home)
        XCTAssertEqual(router.homePath.count, 1)
        XCTAssertEqual(router.homePath.first, .meetingDetail(id: meetingID))
        
        router.navigate(to: .settings, in: .settings)
        XCTAssertEqual(router.settingsPath.count, 1)
        XCTAssertEqual(router.settingsPath.first, .settings)
    }
    
    func test_presentedMeetingDetailID() {
        XCTAssertNil(router.presentedMeetingDetailID)
        let meetingID = UUID()
        router.presentedMeetingDetailID = meetingID
        XCTAssertEqual(router.presentedMeetingDetailID, meetingID)
        XCTAssertEqual(router.homePath.count, 1)
    }
    
    func test_deepLinkMeetingRouting() {
        let meetingID = UUID()
        let url = URL(string: "meetmind://meeting/\(meetingID.uuidString)")!
        
        let handled = router.handleDeepLink(url: url, appState: appState)
        XCTAssertTrue(handled)
        XCTAssertEqual(appState.activeTab, .home)
        XCTAssertEqual(router.presentedMeetingDetailID, meetingID)
    }
    
    func test_deepLinkTabRouting() {
        let url = URL(string: "meetmind://tab/settings")!
        let handled = router.handleDeepLink(url: url, appState: appState)
        XCTAssertTrue(handled)
        XCTAssertEqual(appState.activeTab, .settings)
    }
    
    func test_deepLinkInvalidSchemes() {
        let httpURL = URL(string: "https://meetmind.ai/meeting/123")!
        XCTAssertFalse(router.handleDeepLink(url: httpURL, appState: appState))
        
        let invalidUUIDURL = URL(string: "meetmind://meeting/not-a-uuid")!
        XCTAssertFalse(router.handleDeepLink(url: invalidUUIDURL, appState: appState))
    }
    
    func test_restorationSnapshotCreationAndRestoration() {
        appState.completeOnboarding()
        appState.activeTab = .actionItems
        let detailID = UUID()
        router.presentedMeetingDetailID = detailID
        
        let snapshot = router.createRestorationSnapshot(appState: appState)
        XCTAssertEqual(snapshot.selectedTabIndex, 1)
        XCTAssertEqual(snapshot.presentedMeetingDetailID, detailID)
        XCTAssertTrue(snapshot.hasCompletedOnboarding)
        
        // Fresh state and router
        let freshState = AppState(userDefaults: mockUserDefaults)
        let freshRouter = NavigationRouter()
        
        freshRouter.restore(from: snapshot, appState: freshState)
        XCTAssertEqual(freshState.activeTab, .actionItems)
        XCTAssertTrue(freshState.hasCompletedOnboarding)
        XCTAssertEqual(freshRouter.presentedMeetingDetailID, detailID)
    }
}
