//
//  AppNavigationViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
@testable import MeetMind

/// Comprehensive test suite covering App Lifecycle, Navigation Routing, Onboarding Carousel,
/// Profile & Voice Baseline Setup, Permissions Primer, and Main Tab Navigation Shell.
/// Corresponds to Features 9, 10, 11, 12, and 13.
@MainActor
final class AppNavigationViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var sut: AppNavigationViewModel!
    private var mockUserDefaults: UserDefaults!
    private var testSuiteName: String!
    
    override func setUp() {
        super.setUp()
        testSuiteName = "MeetMindAppNavTests_\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: testSuiteName)
        sut = AppNavigationViewModel(userDefaults: mockUserDefaults)
    }
    
    override func tearDown() {
        mockUserDefaults.removePersistentDomain(forName: testSuiteName)
        mockUserDefaults = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tier 1: Feature 9 (App Lifecycle & Navigation Routing)
    
    /// Tier 1: Feature 9 - Validates that a fresh install with no onboarding flag routes to onboarding.
    func test_tier1_feature9_initialLaunchRoutesToOnboarding() throws {
        XCTAssertFalse(sut.isOnboardingCompleted)
        XCTAssertEqual(sut.rootRoute, .onboarding)
        XCTAssertEqual(sut.currentOnboardingPage, 0)
    }
    
    /// Tier 1: Feature 9 - Validates that marking onboarding complete updates route to main tab shell.
    func test_tier1_feature9_onboardingCompletionNavigatesToMainTab() throws {
        sut.completeOnboarding()
        
        XCTAssertTrue(sut.isOnboardingCompleted)
        XCTAssertEqual(sut.rootRoute, .mainTabs)
        XCTAssertEqual(sut.selectedTab, .home)
    }
    
    /// Tier 1: Feature 9 - Validates push and pop navigation operations within navigation stack.
    func test_tier1_feature9_navigationPathPushAndPop() throws {
        XCTAssertEqual(sut.navigationPath.count, 0)
        
        let destinationId = UUID()
        sut.pushRoute(.meetingDetail(id: destinationId))
        XCTAssertEqual(sut.navigationPath.count, 1)
        XCTAssertEqual(sut.navigationPath.last, .meetingDetail(id: destinationId))
        
        sut.popRoute()
        XCTAssertEqual(sut.navigationPath.count, 0)
    }
    
    /// Tier 1: Feature 9 - Validates popping to root clears all destinations in navigation stack.
    func test_tier1_feature9_popToRootClearsNavigationStack() throws {
        sut.pushRoute(.meetingDetail(id: UUID()))
        sut.pushRoute(.meetingProcessing(id: UUID()))
        sut.pushRoute(.settings)
        XCTAssertEqual(sut.navigationPath.count, 3)
        
        sut.popToRoot()
        XCTAssertEqual(sut.navigationPath.count, 0)
        XCTAssertTrue(sut.navigationPath.isEmpty)
    }
    
    /// Tier 1: Feature 9 - Validates deep link URL parsing routes to specific meeting detail.
    func test_tier1_feature9_deepLinkRoutesToMeetingDetail() throws {
        let targetId = UUID()
        let deepLinkURL = URL(string: "meetmind://meeting/\(targetId.uuidString)")!
        
        let handled = sut.handleDeepLink(url: deepLinkURL)
        XCTAssertTrue(handled)
        XCTAssertEqual(sut.selectedTab, .home)
        XCTAssertEqual(sut.navigationPath.last, .meetingDetail(id: targetId))
    }
    
    // MARK: - Tier 1: Feature 10 (Onboarding Welcome Carousel)
    
    /// Tier 1: Feature 10 - Validates that welcome carousel initializes at page index 0 with 3 total pages.
    func test_tier1_feature10_welcomeCarouselPageCountIsThree() throws {
        XCTAssertEqual(sut.currentOnboardingPage, 0)
        XCTAssertEqual(sut.totalOnboardingPages, 3)
        XCTAssertFalse(sut.isLastOnboardingPage)
    }
    
    /// Tier 1: Feature 10 - Validates advancing carousel sequentially across slides.
    func test_tier1_feature10_welcomeCarouselNextAdvancesIndex() throws {
        XCTAssertEqual(sut.currentOnboardingPage, 0)
        
        sut.nextOnboardingPage()
        XCTAssertEqual(sut.currentOnboardingPage, 1)
        XCTAssertFalse(sut.isLastOnboardingPage)
        
        sut.nextOnboardingPage()
        XCTAssertEqual(sut.currentOnboardingPage, 2)
        XCTAssertTrue(sut.isLastOnboardingPage)
    }
    
    /// Tier 1: Feature 10 - Validates skip button action jumps directly to profile setup stage.
    func test_tier1_feature10_welcomeCarouselSkipButtonJumpsToProfile() throws {
        sut.skipOnboardingCarousel()
        XCTAssertEqual(sut.onboardingStage, .profileSetup)
    }
    
    /// Tier 1: Feature 10 - Validates carousel slide titles match design specifications.
    func test_tier1_feature10_welcomeCarouselSlideContentTitles() throws {
        let pages = sut.carouselPages
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].title, "Intelligent Meeting Notes")
        XCTAssertEqual(pages[1].title, "Real-Time Speech & Diarization")
        XCTAssertEqual(pages[2].title, "Actionable AI Summaries")
    }
    
    /// Tier 1: Feature 10 - Validates previous page navigation decrements index.
    func test_tier1_feature10_welcomeCarouselPreviousPage() throws {
        sut.nextOnboardingPage()
        sut.nextOnboardingPage()
        XCTAssertEqual(sut.currentOnboardingPage, 2)
        
        sut.previousOnboardingPage()
        XCTAssertEqual(sut.currentOnboardingPage, 1)
    }
    
    // MARK: - Tier 1: Feature 11 (Profile & Voice Setup)
    
    /// Tier 1: Feature 11 - Validates user name, email, and role binding.
    func test_tier1_feature11_profileNameAndRoleBinding() throws {
        sut.updateProfile(name: "Sarah Connor", email: "sarah@cyberdyne.com", role: "Product Manager")
        
        XCTAssertEqual(sut.profileName, "Sarah Connor")
        XCTAssertEqual(sut.profileEmail, "sarah@cyberdyne.com")
        XCTAssertEqual(sut.profileRole, "Product Manager")
    }
    
    /// Tier 1: Feature 11 - Validates email syntax validation for well-formed email addresses.
    func test_tier1_feature11_profileEmailValidationAcceptsValidEmail() throws {
        sut.updateProfile(name: "John Doe", email: "john.doe@example.co.uk", role: "Developer")
        XCTAssertTrue(sut.isProfileEmailValid)
    }
    
    /// Tier 1: Feature 11 - Validates voice baseline recording state toggle.
    func test_tier1_feature11_voiceBaselineRecordingStateToggle() throws {
        XCTAssertFalse(sut.isRecordingVoiceBaseline)
        
        sut.startVoiceBaselineRecording()
        XCTAssertTrue(sut.isRecordingVoiceBaseline)
        
        sut.stopVoiceBaselineRecording(sampleURL: URL(fileURLWithPath: "/tmp/voice_sample.m4a"))
        XCTAssertFalse(sut.isRecordingVoiceBaseline)
        XCTAssertTrue(sut.hasVoiceBaseline)
        XCTAssertNotNil(sut.voiceBaselineURL)
    }
    
    /// Tier 1: Feature 11 - Validates voice baseline sample URL persistence.
    func test_tier1_feature11_voiceBaselineAudioURLStored() throws {
        let sampleURL = URL(fileURLWithPath: "/tmp/test_sample_123.m4a")
        sut.saveVoiceBaseline(url: sampleURL)
        
        XCTAssertTrue(sut.hasVoiceBaseline)
        XCTAssertEqual(sut.voiceBaselineURL, sampleURL)
    }
    
    /// Tier 1: Feature 11 - Validates profile continue validation succeeds when required name is provided.
    func test_tier1_feature11_profileContinueValidationWhenValid() throws {
        sut.updateProfile(name: "Alex Rivera", email: "alex@design.io", role: "Designer")
        XCTAssertTrue(sut.isProfileValidForContinue)
        
        sut.advanceFromProfileToPermissions()
        XCTAssertEqual(sut.onboardingStage, .permissionsPrimer)
    }
    
    // MARK: - Tier 1: Feature 12 (Permissions Primer View)
    
    /// Tier 1: Feature 12 - Validates requesting microphone permission updates status flag.
    func test_tier1_feature12_requestMicrophonePermissionUpdatesStatus() throws {
        XCTAssertFalse(sut.isMicrophoneAuthorized)
        
        sut.setMicrophonePermission(authorized: true)
        XCTAssertTrue(sut.isMicrophoneAuthorized)
    }
    
    /// Tier 1: Feature 12 - Validates requesting speech recognition permission updates status flag.
    func test_tier1_feature12_requestSpeechRecognitionUpdatesStatus() throws {
        XCTAssertFalse(sut.isSpeechRecognitionAuthorized)
        
        sut.setSpeechRecognitionPermission(authorized: true)
        XCTAssertTrue(sut.isSpeechRecognitionAuthorized)
    }
    
    /// Tier 1: Feature 12 - Validates all permissions authorized enables enter MeetMind CTA button.
    func test_tier1_feature12_allPermissionsAuthorizedEnablesEnterButton() throws {
        sut.setMicrophonePermission(authorized: true)
        sut.setSpeechRecognitionPermission(authorized: true)
        sut.setCalendarPermission(authorized: true)
        
        XCTAssertTrue(sut.canEnterApplication)
    }
    
    /// Tier 1: Feature 12 - Validates denied permission flags trigger primer settings CTA.
    func test_tier1_feature12_permissionsPrimerDisplaysSettingsPromptWhenDenied() throws {
        sut.setMicrophonePermission(authorized: false)
        sut.setMicrophonePermissionDeniedByUser(true)
        
        XCTAssertTrue(sut.shouldShowSettingsRedirectAlert)
    }
    
    /// Tier 1: Feature 12 - Validates completing permissions primer finishes onboarding flow.
    func test_tier1_feature12_primerDismissNavigationToHome() throws {
        sut.finishPermissionsPrimer()
        
        XCTAssertTrue(sut.isOnboardingCompleted)
        XCTAssertEqual(sut.rootRoute, .mainTabs)
        XCTAssertEqual(sut.selectedTab, .home)
    }
    
    // MARK: - Tier 1: Feature 13 (Main Tab Navigation Shell)
    
    /// Tier 1: Feature 13 - Validates main tab shell initializes with Home as default tab.
    func test_tier1_feature13_mainTabDefaultSelectionIsHome() throws {
        XCTAssertEqual(sut.selectedTab, .home)
    }
    
    /// Tier 1: Feature 13 - Validates tab switching mutations across all 4 root tabs.
    func test_tier1_feature13_mainTabSwitchingUpdatesActiveTab() throws {
        sut.selectTab(.actionItems)
        XCTAssertEqual(sut.selectedTab, .actionItems)
        
        sut.selectTab(.search)
        XCTAssertEqual(sut.selectedTab, .search)
        
        sut.selectTab(.settings)
        XCTAssertEqual(sut.selectedTab, .settings)
        
        sut.selectTab(.home)
        XCTAssertEqual(sut.selectedTab, .home)
    }
    
    /// Tier 1: Feature 13 - Validates updating badge counts for Action Items tab.
    func test_tier1_feature13_mainTabBadgeCountUpdates() throws {
        XCTAssertEqual(sut.actionItemsBadgeCount, 0)
        
        sut.updateActionItemsBadgeCount(5)
        XCTAssertEqual(sut.actionItemsBadgeCount, 5)
    }
    
    /// Tier 1: Feature 13 - Validates re-tapping active tab triggers scroll-to-top callback signal.
    func test_tier1_feature13_mainTabReselectionScrollsToTop() throws {
        sut.selectTab(.home)
        var didTriggerScrollToTop = false
        sut.onScrollToTopRequested = {
            didTriggerScrollToTop = true
        }
        
        sut.handleTabReselection(tab: .home)
        XCTAssertTrue(didTriggerScrollToTop)
    }
    
    /// Tier 1: Feature 13 - Validates that tab switching preserves individual navigation stack depth.
    func test_tier1_feature13_mainTabPreservesStateDuringSwitching() throws {
        sut.selectTab(.home)
        sut.pushRoute(.meetingDetail(id: UUID()))
        XCTAssertEqual(sut.navigationPath.count, 1)
        
        sut.selectTab(.settings)
        XCTAssertEqual(sut.selectedTab, .settings)
        
        sut.selectTab(.home)
        XCTAssertEqual(sut.selectedTab, .home)
        XCTAssertEqual(sut.navigationPath.count, 1)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 9: App Lifecycle & Deep Linking)
    
    /// Tier 2: Feature 9 - Validates handling of invalid or unsupported deep link schemes.
    func test_tier2_feature9_invalidDeepLinkURLHandling() throws {
        let invalidSchemeURL = URL(string: "http://example.com/meeting/123")!
        let handled = sut.handleDeepLink(url: invalidSchemeURL)
        
        XCTAssertFalse(handled)
        XCTAssertEqual(sut.navigationPath.count, 0)
    }
    
    /// Tier 2: Feature 9 - Validates handling of deep link with malformed UUID payload.
    func test_tier2_feature9_deepLinkWithMalformedUUID() throws {
        let malformedURL = URL(string: "meetmind://meeting/not-a-valid-uuid")!
        let handled = sut.handleDeepLink(url: malformedURL)
        
        XCTAssertFalse(handled)
        XCTAssertEqual(sut.navigationPath.count, 0)
    }
    
    /// Tier 2: Feature 9 - Validates corrupt UserDefaults data defaults cleanly to Onboarding.
    func test_tier2_feature9_corruptUserDefaultsFallsBackToOnboarding() throws {
        mockUserDefaults.set("invalid_data_type", forKey: "MeetMind_IsOnboardingCompleted")
        let fallbackSut = AppNavigationViewModel(userDefaults: mockUserDefaults)
        
        XCTAssertFalse(fallbackSut.isOnboardingCompleted)
        XCTAssertEqual(fallbackSut.rootRoute, .onboarding)
    }
    
    /// Tier 2: Feature 9 - Validates rapid push and pop operations preserve stack consistency.
    func test_tier2_feature9_rapidPushAndPopStackIntegrity() throws {
        for _ in 0..<50 {
            sut.pushRoute(.meetingDetail(id: UUID()))
        }
        XCTAssertEqual(sut.navigationPath.count, 50)
        
        for _ in 0..<50 {
            sut.popRoute()
        }
        XCTAssertEqual(sut.navigationPath.count, 0)
        
        // Extra pop on empty stack should not crash
        sut.popRoute()
        XCTAssertEqual(sut.navigationPath.count, 0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 10: Carousel Bounds & Gestures)
    
    /// Tier 2: Feature 10 - Validates carousel index cannot exceed upper bound of available pages.
    func test_tier2_feature10_welcomeCarouselClampsIndexAtUpperBoundary() throws {
        for _ in 0..<10 {
            sut.nextOnboardingPage()
        }
        XCTAssertEqual(sut.currentOnboardingPage, 2)
        XCTAssertTrue(sut.isLastOnboardingPage)
    }
    
    /// Tier 2: Feature 10 - Validates carousel index cannot fall below 0.
    func test_tier2_feature10_welcomeCarouselClampsIndexAtLowerBoundary() throws {
        sut.previousOnboardingPage()
        sut.previousOnboardingPage()
        XCTAssertEqual(sut.currentOnboardingPage, 0)
    }
    
    /// Tier 2: Feature 10 - Validates jumping to an out-of-bounds page index clamps to safe limits.
    func test_tier2_feature10_welcomeCarouselDirectIndexJumpOutOfBounds() throws {
        sut.setOnboardingPage(99)
        XCTAssertEqual(sut.currentOnboardingPage, 2)
        
        sut.setOnboardingPage(-5)
        XCTAssertEqual(sut.currentOnboardingPage, 0)
    }
    
    /// Tier 2: Feature 10 - Validates rapid page transitions do not produce erratic carousel states.
    func test_tier2_feature10_welcomeCarouselRapidSwipeHandling() throws {
        sut.nextOnboardingPage()
        sut.previousOnboardingPage()
        sut.nextOnboardingPage()
        sut.nextOnboardingPage()
        sut.previousOnboardingPage()
        
        XCTAssertEqual(sut.currentOnboardingPage, 1)
        XCTAssertFalse(sut.isLastOnboardingPage)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 11: Profile Validation & Voice Audio)
    
    /// Tier 2: Feature 11 - Validates that an empty display name fails continue validation.
    func test_tier2_feature11_profileEmptyNameValidationFailure() throws {
        sut.updateProfile(name: "", email: "user@domain.com", role: "Engineer")
        XCTAssertFalse(sut.isProfileValidForContinue)
    }
    
    /// Tier 2: Feature 11 - Validates that whitespace-only display name is rejected as invalid.
    func test_tier2_feature11_profileWhitespaceOnlyNameRejected() throws {
        sut.updateProfile(name: "   \t \n ", email: "user@domain.com", role: "Engineer")
        XCTAssertFalse(sut.isProfileValidForContinue)
    }
    
    /// Tier 2: Feature 11 - Validates that exceedingly long profile names (>100 chars) are clamped.
    func test_tier2_feature11_profileNameExceedingMaxLengthTruncation() throws {
        let longName = String(repeating: "A", count: 150)
        sut.updateProfile(name: longName, email: "user@domain.com", role: "Lead")
        
        XCTAssertLessThanOrEqual(sut.profileName.count, 100)
        XCTAssertEqual(sut.profileName.count, 100)
    }
    
    /// Tier 2: Feature 11 - Validates invalid email syntax fails email validity check.
    func test_tier2_feature11_profileInvalidEmailSyntaxRejection() throws {
        let invalidEmails = ["plainaddress", "@missingusername.com", "user@", "user@.com", "user name@domain.com"]
        
        for email in invalidEmails {
            sut.updateProfile(name: "Valid Name", email: email, role: "Tester")
            XCTAssertFalse(sut.isProfileEmailValid, "Email '\(email)' should be rejected.")
        }
    }
    
    /// Tier 2: Feature 11 - Validates voice baseline deletion resets sample state.
    func test_tier2_feature11_profileDeleteVoiceBaselineCleansUpFile() throws {
        let sampleURL = URL(fileURLWithPath: "/tmp/voice_sample.m4a")
        sut.saveVoiceBaseline(url: sampleURL)
        XCTAssertTrue(sut.hasVoiceBaseline)
        
        sut.deleteVoiceBaseline()
        XCTAssertFalse(sut.hasVoiceBaseline)
        XCTAssertNil(sut.voiceBaselineURL)
    }
    
    /// Tier 2: Feature 11 - Validates skipping voice baseline allows continuing with name only.
    func test_tier2_feature11_profileSkipVoiceBaselineAllowsContinue() throws {
        sut.updateProfile(name: "Jane Doe", email: "", role: "")
        sut.skipVoiceBaseline()
        
        XCTAssertTrue(sut.isProfileValidForContinue)
        XCTAssertFalse(sut.hasVoiceBaseline)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 12: Permission Fallbacks & System URLs)
    
    /// Tier 2: Feature 12 - Validates microphone denial produces fallback instructional alert.
    func test_tier2_feature12_microphoneDeniedPrimerShowsFallbackBanner() throws {
        sut.setMicrophonePermission(authorized: false)
        sut.setMicrophonePermissionDeniedByUser(true)
        
        XCTAssertFalse(sut.isMicrophoneAuthorized)
        XCTAssertTrue(sut.shouldShowSettingsRedirectAlert)
        XCTAssertEqual(sut.permissionStatusDescription, "Microphone access is required to record meetings.")
    }
    
    /// Tier 2: Feature 12 - Validates partial permissions enable limited operational mode.
    func test_tier2_feature12_partialPermissionsGrantedEnablesLimitedMode() throws {
        sut.setMicrophonePermission(authorized: true)
        sut.setSpeechRecognitionPermission(authorized: false)
        
        XCTAssertTrue(sut.isMicrophoneAuthorized)
        XCTAssertFalse(sut.isSpeechRecognitionAuthorized)
        XCTAssertTrue(sut.hasPartialPermissions)
    }
    
    /// Tier 2: Feature 12 - Validates that repeated permission grant calls are idempotent.
    func test_tier2_feature12_repeatedPermissionRequestsAreIdempotent() throws {
        sut.setMicrophonePermission(authorized: true)
        sut.setMicrophonePermission(authorized: true)
        sut.setMicrophonePermission(authorized: true)
        
        XCTAssertTrue(sut.isMicrophoneAuthorized)
    }
    
    /// Tier 2: Feature 12 - Validates system settings redirect URL formation.
    func test_tier2_feature12_permissionsPrimerSystemSettingsURLValid() throws {
        let settingsURL = sut.systemSettingsURL
        XCTAssertNotNil(settingsURL)
        XCTAssertEqual(settingsURL?.scheme, "app-settings")
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 13: Tab Shell Edge Cases & Badges)
    
    /// Tier 2: Feature 13 - Validates rapid tab switching does not corrupt selectedTab state.
    func test_tier2_feature13_rapidTabSwitchingMaintainsConsistency() throws {
        let tabs: [TabIdentifier] = [.home, .actionItems, .search, .settings]
        for _ in 0..<100 {
            let nextTab = tabs.randomElement()!
            sut.selectTab(nextTab)
            XCTAssertEqual(sut.selectedTab, nextTab)
        }
    }
    
    /// Tier 2: Feature 13 - Validates negative badge count values are clamped to 0.
    func test_tier2_feature13_badgeCountNegativeClampsToZero() throws {
        sut.updateActionItemsBadgeCount(-10)
        XCTAssertEqual(sut.actionItemsBadgeCount, 0)
    }
    
    /// Tier 2: Feature 13 - Validates badge overflow (>99) formats as "99+".
    func test_tier2_feature13_badgeCountOverflowDisplays99Plus() throws {
        sut.updateActionItemsBadgeCount(120)
        XCTAssertEqual(sut.actionItemsBadgeCount, 120)
        XCTAssertEqual(sut.formattedActionItemsBadge, "99+")
        
        sut.updateActionItemsBadgeCount(42)
        XCTAssertEqual(sut.formattedActionItemsBadge, "42")
        
        sut.updateActionItemsBadgeCount(0)
        XCTAssertNil(sut.formattedActionItemsBadge)
    }
}
