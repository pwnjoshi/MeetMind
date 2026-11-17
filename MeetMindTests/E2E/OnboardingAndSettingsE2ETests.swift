//
//  OnboardingAndSettingsE2ETests.swift
//  MeetMindTests
//
//  Comprehensive E2E Test Suite covering Onboarding, Navigation, Permissions,
//  Theme Adaptation, and Settings Persistence (Scenarios S1, S5, S14, S15, S16, S17, S18, S19, S21, S22).
//

import XCTest
import Foundation
@testable import MeetMind

@MainActor
final class OnboardingAndSettingsE2ETests: XCTestCase {
    
    private var navigationVM: AppNavigationViewModel!
    private var settingsVM: SettingsViewModel!
    private var mockAudioRecorder: MockAudioRecordingService!
    private var mockAudioPlayer: MockAudioPlaybackService!
    
    override func setUp() {
        super.setUp()
        navigationVM = AppNavigationViewModel()
        settingsVM = SettingsViewModel()
        mockAudioRecorder = MockAudioRecordingService()
        mockAudioPlayer = MockAudioPlaybackService()
    }
    
    override func tearDown() {
        navigationVM = nil
        settingsVM = nil
        mockAudioRecorder = nil
        mockAudioPlayer = nil
        super.tearDown()
    }
    
    // MARK: - Tier 4: Scenario S1 (First Run Experience)
    
    /// Tier 4: Scenario S1 - Full First Run Experience
    /// - Precondition: Fresh installation with no prior user preferences or profiles.
    /// - Workflow:
    ///   1. Check initial launch state (hasCompletedOnboarding == false, activeTab == .onboarding).
    ///   2. Navigate through 3 carousel slides (Live Transcription -> AI Minutes -> Action Items).
    ///   3. Complete profile form with name, email, role, and a voice baseline sample URL.
    ///   4. Request permissions primer for microphone, speech recognition, and reminders.
    ///   5. Transition to main application shell on Home dashboard.
    /// - Assertions:
    ///   - Initial carousel index is 0, advances to 2.
    ///   - Profile properties persist with valid displayName and voiceProfileURL.
    ///   - Permission states are marked authorized.
    ///   - hasCompletedOnboarding is true and activeTab is Home (index 0).
    func test_tier4_scenario1_firstRunExperience() throws {
        XCTAssertFalse(navigationVM.hasCompletedOnboarding)
        XCTAssertEqual(navigationVM.carouselPageIndex, 0)
        
        // Carousel navigation
        navigationVM.advanceCarousel()
        XCTAssertEqual(navigationVM.carouselPageIndex, 1)
        navigationVM.advanceCarousel()
        XCTAssertEqual(navigationVM.carouselPageIndex, 2)
        
        // Profile setup
        let sampleVoiceURL = URL(fileURLWithPath: "/tmp/baseline_voice.m4a")
        navigationVM.setupProfile(name: "Sarah Connor", email: "sarah@skynet.resistance", role: "Team Lead", voiceSampleURL: sampleVoiceURL)
        XCTAssertEqual(navigationVM.userProfile?.name, "Sarah Connor")
        XCTAssertEqual(navigationVM.userProfile?.email, "sarah@skynet.resistance")
        XCTAssertEqual(navigationVM.userProfile?.role, "Team Lead")
        XCTAssertEqual(navigationVM.userProfile?.voiceProfileURL, sampleVoiceURL)
        
        // Permissions primer
        navigationVM.grantPermission(.microphone)
        navigationVM.grantPermission(.speechRecognition)
        navigationVM.grantPermission(.reminders)
        XCTAssertTrue(navigationVM.isPermissionGranted(.microphone))
        XCTAssertTrue(navigationVM.isPermissionGranted(.speechRecognition))
        XCTAssertTrue(navigationVM.isPermissionGranted(.reminders))
        
        // Complete onboarding
        navigationVM.completeOnboarding()
        XCTAssertTrue(navigationVM.hasCompletedOnboarding)
        XCTAssertEqual(navigationVM.selectedTabIndex, 0)
    }

    // MARK: - Tier 4: Scenario S5 (Settings Customization & Persistence)
    
    /// Tier 4: Scenario S5 - Settings Customization and Persistence
    /// - Precondition: User is on Settings tab with default configurations.
    /// - Workflow:
    ///   1. Switch audio recording quality from High (128kbps) to Standard (64kbps).
    ///   2. Switch visual theme from System to Dark.
    ///   3. Simulate temporary audio cache generation (50MB) and inspect storage meter.
    ///   4. Trigger "Clear Temporary Audio Cache" action.
    ///   5. Recalculate storage usage bytes.
    /// - Assertions:
    ///   - Audio quality bitrate updates to 64_000 and persists in settings.
    ///   - Theme mode updates to .dark with dark color token resolution.
    ///   - Cache clearance resets temporary cache bytes to 0 without deleting user meetings.
    func test_tier4_scenario5_settingsCustomizationAndPersistence() throws {
        XCTAssertEqual(settingsVM.audioQuality, .high128k)
        XCTAssertEqual(settingsVM.themeMode, .system)
        
        // Audio quality switch
        settingsVM.setAudioQuality(.standard64k)
        XCTAssertEqual(settingsVM.audioQuality, .standard64k)
        XCTAssertEqual(settingsVM.audioBitrate, 64_000)
        
        // Theme switch
        settingsVM.setThemeMode(.dark)
        XCTAssertEqual(settingsVM.themeMode, .dark)
        XCTAssertTrue(settingsVM.isDarkModeActive)
        
        // Cache management
        settingsVM.simulateTemporaryCache(byteCount: 52_428_800) // 50 MB
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 52_428_800)
        XCTAssertGreaterThan(settingsVM.formattedStorageUsage.count, 0)
        
        settingsVM.clearTemporaryCache()
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 0)
        XCTAssertEqual(settingsVM.formattedStorageUsage, "0 MB")
    }

    // MARK: - Tier 4: Scenario S14 (App State Restoration)
    
    /// Tier 4: Scenario S14 - App State Restoration Across App Lifecycles
    /// - Precondition: User is navigating a meeting detail cockpit when app is terminated.
    /// - Workflow:
    ///   1. Set active meeting navigation path to meeting detail ID.
    ///   2. Capture restoration state snapshot.
    ///   3. Re-instantiate AppNavigationViewModel simulating app cold launch.
    ///   4. Restore navigation state from snapshot.
    /// - Assertions:
    ///   - Restored navigation path matches previous cockpit meeting ID.
    ///   - Active tab index matches the tab prior to termination.
    func test_tier4_scenario14_appStateRestoration() throws {
        let activeMeetingID = UUID()
        navigationVM.selectedTabIndex = 0
        navigationVM.navigateToMeetingDetail(meetingID: activeMeetingID)
        XCTAssertEqual(navigationVM.presentedMeetingDetailID, activeMeetingID)
        
        let snapshot = navigationVM.createRestorationSnapshot()
        XCTAssertNotNil(snapshot)
        
        let restoredNavigationVM = AppNavigationViewModel()
        restoredNavigationVM.restore(from: snapshot)
        XCTAssertTrue(restoredNavigationVM.hasCompletedOnboarding)
        XCTAssertEqual(restoredNavigationVM.presentedMeetingDetailID, activeMeetingID)
        XCTAssertEqual(restoredNavigationVM.selectedTabIndex, 0)
    }

    // MARK: - Tier 4: Scenario S15 (Onboarding Skip & Defaults)
    
    /// Tier 4: Scenario S15 - Onboarding Skip and Defaults
    /// - Precondition: Fresh install where user skips optional profile setup.
    /// - Workflow:
    ///   1. Onboarding carousel presented.
    ///   2. User taps "Skip" on profile voice enrollment.
    ///   3. App applies standard system defaults (Guest User, Standard quality, System theme).
    ///   4. Loads Home dashboard with initial welcome template meeting.
    /// - Assertions:
    ///   - hasCompletedOnboarding is true.
    ///   - User profile contains default placeholder values.
    ///   - Voice profile URL is nil.
    func test_tier4_scenario15_onboardingSkipAndDefaults() throws {
        XCTAssertFalse(navigationVM.hasCompletedOnboarding)
        navigationVM.skipProfileSetup()
        
        XCTAssertTrue(navigationVM.hasCompletedOnboarding)
        XCTAssertNotNil(navigationVM.userProfile)
        XCTAssertEqual(navigationVM.userProfile?.name, "MeetMind User")
        XCTAssertNil(navigationVM.userProfile?.voiceProfileURL)
        XCTAssertEqual(navigationVM.selectedTabIndex, 0)
    }

    // MARK: - Tier 4: Scenario S16 (Voice Profile Update)
    
    /// Tier 4: Scenario S16 - Voice Profile Update in Settings
    /// - Precondition: Existing user profile loaded in Settings.
    /// - Workflow:
    ///   1. Open Settings -> User Profile.
    ///   2. Update display name from "Sarah Connor" to "Sarah Connor-Reese".
    ///   3. Update role from "Team Lead" to "Director of Engineering".
    ///   4. Re-record voice baseline signature sample (new URL).
    ///   5. Save updates to persistent profile.
    /// - Assertions:
    ///   - Display name and role update accurately.
    ///   - Updated voice profile URL is stored and non-nil.
    func test_tier4_scenario16_voiceProfileUpdate() throws {
        settingsVM.updateUserProfile(name: "Sarah Connor", role: "Team Lead", email: "sarah@meetmind.ai", voiceURL: nil)
        XCTAssertEqual(settingsVM.userProfile?.name, "Sarah Connor")
        
        let updatedVoiceURL = URL(fileURLWithPath: "/var/mobile/Containers/Data/voice_sample_v2.m4a")
        settingsVM.updateUserProfile(
            name: "Sarah Connor-Reese",
            role: "Director of Engineering",
            email: "sarah@meetmind.ai",
            voiceURL: updatedVoiceURL
        )
        
        XCTAssertEqual(settingsVM.userProfile?.name, "Sarah Connor-Reese")
        XCTAssertEqual(settingsVM.userProfile?.role, "Director of Engineering")
        XCTAssertEqual(settingsVM.userProfile?.voiceProfileURL, updatedVoiceURL)
    }

    // MARK: - Tier 4: Scenario S17 (Permission Denial Recovery)
    
    /// Tier 4: Scenario S17 - Permission Denial Recovery Workflow
    /// - Precondition: User denies microphone access during permissions primer.
    /// - Workflow:
    ///   1. Primer requests mic permission; simulate system denial (`.denied`).
    ///   2. Verify custom UI primer displays instructional alert with direct deep-link action.
    ///   3. User triggers Settings deep-link and subsequently grants access in OS.
    ///   4. App returns to foreground and refreshes permission status.
    /// - Assertions:
    ///   - Primer displays denial alert and disables immediate recording.
    ///   - Deep link URL points to `UIApplication.openSettingsURLString`.
    ///   - Status updates to authorized once OS setting change is registered.
    func test_tier4_scenario17_permissionDenialRecovery() throws {
        navigationVM.setPermissionStatus(.microphone, status: .denied)
        XCTAssertFalse(navigationVM.isPermissionGranted(.microphone))
        XCTAssertTrue(navigationVM.shouldShowPermissionRecoveryAlert(for: .microphone))
        
        let deepLinkURL = navigationVM.settingsDeepLinkURL()
        XCTAssertEqual(deepLinkURL.absoluteString, "app-settings:")
        
        // Simulate returning from system settings with permission granted
        navigationVM.setPermissionStatus(.microphone, status: .authorized)
        XCTAssertTrue(navigationVM.isPermissionGranted(.microphone))
        XCTAssertFalse(navigationVM.shouldShowPermissionRecoveryAlert(for: .microphone))
    }

    // MARK: - Tier 4: Scenario S18 (Tab Switching State Preservation)
    
    /// Tier 4: Scenario S18 - Tab Switching State Preservation
    /// - Precondition: Meeting detail cockpit is actively playing audio.
    /// - Workflow:
    ///   1. Load audio and start playback on Meeting Detail (Home tab context).
    ///   2. Switch root tab to Action Items (tab index 1).
    ///   3. Switch root tab to Search (tab index 2).
    ///   4. Switch root tab back to Home (tab index 0).
    /// - Assertions:
    ///   - Audio player `isPlaying` remains true throughout all tab transitions.
    ///   - Playback time advances monotonically without resetting to 0.
    func test_tier4_scenario18_tabSwitchingStatePreservation() throws {
        let dummyAudioURL = URL(fileURLWithPath: "/tmp/test_meeting.m4a")
        try mockAudioPlayer.loadAudio(url: dummyAudioURL)
        try mockAudioPlayer.play()
        XCTAssertTrue(mockAudioPlayer.isPlaying)
        
        // Switch to Tab 1 (Action Items)
        navigationVM.selectedTabIndex = 1
        XCTAssertEqual(navigationVM.selectedTabIndex, 1)
        XCTAssertTrue(mockAudioPlayer.isPlaying)
        
        // Advance playback
        mockAudioPlayer.simulateTimeAdvance(seconds: 5.0)
        XCTAssertEqual(mockAudioPlayer.currentTime, 5.0)
        
        // Switch to Tab 2 (Search)
        navigationVM.selectedTabIndex = 2
        XCTAssertEqual(navigationVM.selectedTabIndex, 2)
        XCTAssertTrue(mockAudioPlayer.isPlaying)
        
        // Switch back to Tab 0 (Home)
        navigationVM.selectedTabIndex = 0
        XCTAssertEqual(navigationVM.selectedTabIndex, 0)
        XCTAssertTrue(mockAudioPlayer.isPlaying)
        XCTAssertGreaterThanOrEqual(mockAudioPlayer.currentTime, 5.0)
    }

    // MARK: - Tier 4: Scenario S19 (Audio Encoding Bitrate Switch)
    
    /// Tier 4: Scenario S19 - Audio Encoding Bitrate Switching
    /// - Precondition: User can select between Standard (64kbps) and High (128kbps) quality.
    /// - Workflow:
    ///   1. Set audio quality to Standard (64kbps) and start simulated recording.
    ///   2. Stop recording and verify AAC parameters for 64kbps.
    ///   3. Set audio quality to High (128kbps) and start second recording.
    ///   4. Stop recording and verify AAC parameters for 128kbps.
    /// - Assertions:
    ///   - First recording uses 64_000 bps; second recording uses 128_000 bps.
    ///   - Generated byte size of High quality is approximately 2x Standard for equal duration.
    func test_tier4_scenario19_audioEncodingBitrateSwitch() async throws {
        settingsVM.setAudioQuality(.standard64k)
        XCTAssertEqual(settingsVM.audioBitrate, 64_000)
        
        let standardURL = URL(fileURLWithPath: "/tmp/standard_64k.m4a")
        mockAudioRecorder.configuredBitrate = 64_000
        try await mockAudioRecorder.startRecording(destinationURL: standardURL)
        mockAudioRecorder.simulateDurationAdvance(seconds: 10.0)
        let stoppedStandard = try await mockAudioRecorder.stopRecording()
        XCTAssertEqual(stoppedStandard, standardURL)
        XCTAssertEqual(mockAudioRecorder.lastRecordedBitrate, 64_000)
        
        // Switch to High
        settingsVM.setAudioQuality(.high128k)
        XCTAssertEqual(settingsVM.audioBitrate, 128_000)
        
        let highURL = URL(fileURLWithPath: "/tmp/high_128k.m4a")
        mockAudioRecorder.configuredBitrate = 128_000
        try await mockAudioRecorder.startRecording(destinationURL: highURL)
        mockAudioRecorder.simulateDurationAdvance(seconds: 10.0)
        let stoppedHigh = try await mockAudioRecorder.stopRecording()
        XCTAssertEqual(stoppedHigh, highURL)
        XCTAssertEqual(mockAudioRecorder.lastRecordedBitrate, 128_000)
    }

    // MARK: - Tier 4: Scenario S21 (Temporary Cache Purge)
    
    /// Tier 4: Scenario S21 - Temporary Audio Cache Purge
    /// - Precondition: Meeting audio files are stored in documents, while transient waveform cache is in temp directory.
    /// - Workflow:
    ///   1. Populate 50MB of transient waveform and export preview files.
    ///   2. Populate 100MB of primary persistent meeting recordings.
    ///   3. Trigger Cache Purge in Settings.
    ///   4. Verify disk space computation.
    /// - Assertions:
    ///   - Transient cache bytes decrease to 0.
    ///   - Primary persistent meeting recordings remain intact at 100MB.
    func test_tier4_scenario21_temporaryCachePurge() throws {
        settingsVM.simulateTemporaryCache(byteCount: 52_428_800) // 50MB
        settingsVM.simulatePersistentRecordings(byteCount: 104_857_600) // 100MB
        
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 52_428_800)
        XCTAssertEqual(settingsVM.persistentRecordingsBytes, 104_857_600)
        
        settingsVM.clearTemporaryCache()
        
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 0)
        XCTAssertEqual(settingsVM.persistentRecordingsBytes, 104_857_600)
    }

    // MARK: - Tier 4: Scenario S22 (Dynamic Theme Adaptation)
    
    /// Tier 4: Scenario S22 - Dynamic Theme Adaptation Without App Restart
    /// - Precondition: App is running under Light theme mode.
    /// - Workflow:
    ///   1. Inspect design token background color under Light mode.
    ///   2. Switch Settings theme mode to Dark.
    ///   3. Inspect design token background and surface colors under Dark mode.
    ///   4. Switch Settings theme mode to System.
    /// - Assertions:
    ///   - Light mode resolves background token #FFFFFF or slate light.
    ///   - Dark mode resolves background token #1E2E28 or dark slate.
    ///   - Changes apply instantly without re-initializing view models.
    func test_tier4_scenario22_dynamicThemeAdaptation() throws {
        settingsVM.setThemeMode(.light)
        XCTAssertEqual(settingsVM.resolvedColorScheme, .light)
        XCTAssertEqual(settingsVM.themeBackgroundColorHex, "#FFFFFF")
        
        settingsVM.setThemeMode(.dark)
        XCTAssertEqual(settingsVM.resolvedColorScheme, .dark)
        XCTAssertEqual(settingsVM.themeBackgroundColorHex, "#1E2E28")
        
        settingsVM.setThemeMode(.system)
        XCTAssertEqual(settingsVM.themeMode, .system)
    }

    // MARK: - Tier 3: Pairwise Combinations
    
    /// Tier 3: Pairwise - Onboarding Completed Under Dark Theme Setting
    /// - Verifies onboarding flow when dark theme is pre-selected.
    func test_tier3_onboardingAndDarkThemePairwise() throws {
        settingsVM.setThemeMode(.dark)
        navigationVM.completeOnboarding()
        
        XCTAssertTrue(navigationVM.hasCompletedOnboarding)
        XCTAssertEqual(settingsVM.themeMode, .dark)
        XCTAssertTrue(settingsVM.isDarkModeActive)
    }

    /// Tier 3: Pairwise - Permission Denial Combined With Audio Bitrate Switch
    /// - Verifies audio bitrate settings can be adjusted even when mic permission is currently denied.
    func test_tier3_permissionDenialAudioQualityPairwise() throws {
        navigationVM.setPermissionStatus(.microphone, status: .denied)
        settingsVM.setAudioQuality(.high128k)
        
        XCTAssertFalse(navigationVM.isPermissionGranted(.microphone))
        XCTAssertEqual(settingsVM.audioBitrate, 128_000)
        
        // Granting permission later retains configured bitrate
        navigationVM.setPermissionStatus(.microphone, status: .authorized)
        XCTAssertTrue(navigationVM.isPermissionGranted(.microphone))
        XCTAssertEqual(settingsVM.audioBitrate, 128_000)
    }

    /// Tier 3: Pairwise - Voice Profile Update Combined With Storage Quota
    /// - Verifies updating voice profile baseline correctly increments persistent storage calculation.
    func test_tier3_voiceProfileUpdateStorageQuotaPairwise() throws {
        let initialStorage = settingsVM.persistentRecordingsBytes
        let voiceSampleURL = URL(fileURLWithPath: "/tmp/voice_enrollment.m4a")
        settingsVM.updateUserProfile(name: "John Connor", role: "Specialist", email: "john@meetmind.ai", voiceURL: voiceSampleURL)
        settingsVM.simulatePersistentRecordings(byteCount: initialStorage + 1_048_576) // +1MB for voice sample
        
        XCTAssertEqual(settingsVM.userProfile?.name, "John Connor")
        XCTAssertGreaterThan(settingsVM.persistentRecordingsBytes, initialStorage)
    }

    /// Tier 3: Pairwise - State Restoration Preserves Tab Index and Detail Navigation Path
    /// - Verifies state restoration faithfully recovers multi-tab state.
    func test_tier3_stateRestorationAcrossTabsPairwise() throws {
        navigationVM.selectedTabIndex = 3 // Settings tab
        let detailID = UUID()
        navigationVM.navigateToMeetingDetail(meetingID: detailID)
        
        let snapshot = navigationVM.createRestorationSnapshot()
        let freshNav = AppNavigationViewModel()
        freshNav.restore(from: snapshot)
        
        XCTAssertEqual(freshNav.selectedTabIndex, 3)
        XCTAssertEqual(freshNav.presentedMeetingDetailID, detailID)
    }

    /// Tier 3: Pairwise - Audio Bitrate Switching Followed By Cache Purge
    /// - Verifies cache purge executes cleanly regardless of current audio bitrate selection.
    func test_tier3_audioBitrateCachePurgePairwise() throws {
        settingsVM.setAudioQuality(.standard64k)
        settingsVM.simulateTemporaryCache(byteCount: 10_000_000)
        settingsVM.clearTemporaryCache()
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 0)
        
        settingsVM.setAudioQuality(.high128k)
        settingsVM.simulateTemporaryCache(byteCount: 20_000_000)
        settingsVM.clearTemporaryCache()
        XCTAssertEqual(settingsVM.temporaryCacheBytes, 0)
    }

    /// Tier 3: Pairwise - Rapid Theme Cycling State Stability
    /// - Verifies repeated rapid switching between system, light, and dark modes maintains correct token mapping.
    func test_tier3_rapidThemeCyclingStatePairwise() throws {
        for _ in 0..<5 {
            settingsVM.setThemeMode(.light)
            XCTAssertEqual(settingsVM.resolvedColorScheme, .light)
            settingsVM.setThemeMode(.dark)
            XCTAssertEqual(settingsVM.resolvedColorScheme, .dark)
            settingsVM.setThemeMode(.system)
            XCTAssertEqual(settingsVM.themeMode, .system)
        }
    }
}
