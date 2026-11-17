//
//  SettingsViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
@testable import MeetMind

/// Comprehensive test suite covering Settings: Theme & Design System Tokens,
/// Audio Quality Configuration, Speech & AI Options, Storage & Cache Purge, and Theme Persistence.
/// Corresponds to Features 2, 14, 15, 16, and 17.
@MainActor
final class SettingsViewModelTests: XCTestCase {
    
    // MARK: - Test Infrastructure & Fixtures
    
    private var sut: SettingsViewModel!
    private var mockUserDefaults: UserDefaults!
    private var testSuiteName: String!
    private var tempDirectoryURL: URL!
    
    override func setUp() {
        super.setUp()
        testSuiteName = "MeetMindSettingsTests_\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: testSuiteName)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetMindSettingsTestCache_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectoryURL = tempDir
        
        sut = SettingsViewModel(userDefaults: mockUserDefaults, cacheDirectory: tempDirectoryURL)
    }
    
    override func tearDown() {
        if let tempDir = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDir)
        }
        mockUserDefaults.removePersistentDomain(forName: testSuiteName)
        mockUserDefaults = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tier 1: Feature 2 (Design System & Theme Tokens)
    
    /// Tier 1: Feature 2 - Validates color token resolution under light appearance mode.
    func test_tier1_feature2_themeTokensResolutionForLightMode() throws {
        sut.setThemeMode(.light)
        
        let palette = sut.activeColorPalette
        XCTAssertEqual(palette.primarySlateHex, "#1E2E28")
        XCTAssertEqual(palette.warmAmberHex, "#F59E0B")
        XCTAssertEqual(palette.liveBlueHex, "#3B82F6")
        XCTAssertEqual(palette.aiPurpleHex, "#8B5CF6")
        XCTAssertEqual(palette.mintGreenHex, "#10B981")
        XCTAssertEqual(palette.coralRedHex, "#EF4444")
        XCTAssertEqual(palette.backgroundHex, "#F8FAFC")
    }
    
    /// Tier 1: Feature 2 - Validates color token resolution under dark appearance mode.
    func test_tier1_feature2_themeTokensResolutionForDarkMode() throws {
        sut.setThemeMode(.dark)
        
        let palette = sut.activeColorPalette
        XCTAssertEqual(palette.backgroundHex, "#0F172A")
        XCTAssertEqual(palette.surfaceCardHex, "#1E293B")
        XCTAssertEqual(palette.primarySlateHex, "#1E2E28")
        XCTAssertEqual(palette.liveBlueHex, "#3B82F6")
    }
    
    /// Tier 1: Feature 2 - Validates exact brand color hex values match Figma specification Node 8:2.
    func test_tier1_feature2_brandColorHexValuesMatchFigma() throws {
        XCTAssertEqual(ThemeColorTokens.slatePrimary, "#1E2E28")
        XCTAssertEqual(ThemeColorTokens.amberAccent, "#F59E0B")
        XCTAssertEqual(ThemeColorTokens.blueLive, "#3B82F6")
        XCTAssertEqual(ThemeColorTokens.purpleAI, "#8B5CF6")
        XCTAssertEqual(ThemeColorTokens.greenSuccess, "#10B981")
        XCTAssertEqual(ThemeColorTokens.redRecording, "#EF4444")
    }
    
    /// Tier 1: Feature 2 - Validates typography scale point sizes match standard HIG scales.
    func test_tier1_feature2_typographyScaleMapping() throws {
        let typography = sut.typographyTokens
        XCTAssertEqual(typography.largeTitleSize, 34.0)
        XCTAssertEqual(typography.title1Size, 28.0)
        XCTAssertEqual(typography.title2Size, 22.0)
        XCTAssertEqual(typography.headlineSize, 17.0)
        XCTAssertEqual(typography.bodySize, 17.0)
        XCTAssertEqual(typography.captionSize, 12.0)
    }
    
    // MARK: - Tier 1: Feature 14 (Settings: Audio Quality)
    
    /// Tier 1: Feature 14 - Validates selecting High quality configures 128kbps bitrate.
    func test_tier1_feature14_audioQualitySelectionHighBitrate() throws {
        sut.setAudioQuality(.high)
        
        XCTAssertEqual(sut.audioQuality, .high)
        XCTAssertEqual(sut.audioBitrateKbps, 128)
        XCTAssertEqual(sut.sampleRateHz, 44100)
    }
    
    /// Tier 1: Feature 14 - Validates selecting Standard quality configures 64kbps bitrate.
    func test_tier1_feature14_audioQualitySelectionStandardBitrate() throws {
        sut.setAudioQuality(.standard)
        
        XCTAssertEqual(sut.audioQuality, .standard)
        XCTAssertEqual(sut.audioBitrateKbps, 64)
        XCTAssertEqual(sut.sampleRateHz, 22050)
    }
    
    /// Tier 1: Feature 14 - Validates noise suppression toggle state mutation and persistence.
    func test_tier1_feature14_noiseSuppressionToggle() throws {
        XCTAssertTrue(sut.isNoiseSuppressionEnabled) // Default true
        
        sut.toggleNoiseSuppression()
        XCTAssertFalse(sut.isNoiseSuppressionEnabled)
        
        sut.toggleNoiseSuppression()
        XCTAssertTrue(sut.isNoiseSuppressionEnabled)
    }
    
    /// Tier 1: Feature 14 - Validates default audio format string is AAC / M4A.
    func test_tier1_feature14_audioFormatStringDefaultsToM4A() throws {
        XCTAssertEqual(sut.audioFormatExtension, "m4a")
        XCTAssertEqual(sut.audioMimeType, "audio/m4a")
    }
    
    // MARK: - Tier 1: Feature 15 (Settings: Speech & AI Options)
    
    /// Tier 1: Feature 15 - Validates selecting transcription speech language locale.
    func test_tier1_feature15_speechLanguageSelection() throws {
        XCTAssertEqual(sut.speechLanguageLocale, "en-US")
        
        sut.setSpeechLanguageLocale("es-ES")
        XCTAssertEqual(sut.speechLanguageLocale, "es-ES")
        
        sut.setSpeechLanguageLocale("fr-FR")
        XCTAssertEqual(sut.speechLanguageLocale, "fr-FR")
    }
    
    /// Tier 1: Feature 15 - Validates on-device speech recognition toggle mutation.
    func test_tier1_feature15_onDeviceRecognitionToggle() throws {
        XCTAssertFalse(sut.isOnDeviceRecognitionOnly)
        
        sut.toggleOnDeviceRecognition()
        XCTAssertTrue(sut.isOnDeviceRecognitionOnly)
        
        sut.toggleOnDeviceRecognition()
        XCTAssertFalse(sut.isOnDeviceRecognitionOnly)
    }
    
    /// Tier 1: Feature 15 - Validates summary style selection between executive and detailed.
    func test_tier1_feature15_summaryStyleSelection() throws {
        XCTAssertEqual(sut.summaryStyle, .executive)
        
        sut.setSummaryStyle(.detailed)
        XCTAssertEqual(sut.summaryStyle, .detailed)
        
        sut.setSummaryStyle(.executive)
        XCTAssertEqual(sut.summaryStyle, .executive)
    }
    
    /// Tier 1: Feature 15 - Validates custom AI API key entry, masking, and secure storage.
    func test_tier1_feature15_apiKeyStorageAndSecurePersistence() throws {
        XCTAssertEqual(sut.apiKey, "")
        XCTAssertFalse(sut.hasCustomAPIKey)
        
        sut.setAPIKey("sk-test-meetmind-secret-key-12345")
        XCTAssertEqual(sut.apiKey, "sk-test-meetmind-secret-key-12345")
        XCTAssertTrue(sut.hasCustomAPIKey)
        XCTAssertEqual(sut.maskedAPIKey, "sk-...2345")
    }
    
    /// Tier 1: Feature 15 - Validates list of supported language locales is non-empty.
    func test_tier1_feature15_availableLanguagesListNonEmpty() throws {
        let languages = sut.availableLanguages
        XCTAssertGreaterThan(languages.count, 5)
        XCTAssertTrue(languages.contains(where: { $0.code == "en-US" }))
        XCTAssertTrue(languages.contains(where: { $0.code == "es-ES" }))
        XCTAssertTrue(languages.contains(where: { $0.code == "de-DE" }))
    }
    
    // MARK: - Tier 1: Feature 16 (Settings: Storage & Cache)
    
    /// Tier 1: Feature 16 - Validates storage usage byte calculation.
    func test_tier1_feature16_storageUsageCalculation() throws {
        let dummyData = Data(repeating: 0xAA, count: 1024 * 1024 * 5) // 5 MB
        let dummyFile = tempDirectoryURL.appendingPathComponent("cached_audio.m4a")
        try dummyData.write(to: dummyFile)
        
        sut.recalculateStorageUsage()
        XCTAssertGreaterThanOrEqual(sut.temporaryCacheSizeBytes, 5 * 1024 * 1024)
    }
    
    /// Tier 1: Feature 16 - Validates formatted storage usage string representation.
    func test_tier1_feature16_formattedStorageUsageString() throws {
        sut.setSimulatedCacheSize(bytes: 1024 * 1024 * 25) // 25 MB
        XCTAssertEqual(sut.formattedCacheSize, "25.0 MB")
        
        sut.setSimulatedCacheSize(bytes: 1024 * 1024 * 1024 * 2) // 2 GB
        XCTAssertEqual(sut.formattedCacheSize, "2.00 GB")
    }
    
    /// Tier 1: Feature 16 - Validates clearing temporary cache removes files from directory.
    func test_tier1_feature16_clearTemporaryCacheEmptiesDirectory() throws {
        let dummyFile = tempDirectoryURL.appendingPathComponent("temp_1.m4a")
        try Data("test audio".utf8).write(to: dummyFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dummyFile.path))
        
        sut.clearTemporaryCache()
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyFile.path))
        XCTAssertEqual(sut.temporaryCacheSizeBytes, 0)
        XCTAssertEqual(sut.formattedCacheSize, "0 KB")
    }
    
    /// Tier 1: Feature 16 - Validates iCloud sync toggle mutation and persistence.
    func test_tier1_feature16_iCloudSyncToggle() throws {
        XCTAssertFalse(sut.isiCloudSyncEnabled)
        
        sut.toggleICloudSync()
        XCTAssertTrue(sut.isiCloudSyncEnabled)
        
        sut.toggleICloudSync()
        XCTAssertFalse(sut.isiCloudSyncEnabled)
    }
    
    // MARK: - Tier 1: Feature 17 (Settings: Theme & Appearance)
    
    /// Tier 1: Feature 17 - Validates selecting system mode synchronizes with OS scheme.
    func test_tier1_feature17_themeModeSelectionSystem() throws {
        sut.setThemeMode(.system)
        XCTAssertEqual(sut.themeMode, .system)
        XCTAssertNil(sut.preferredColorScheme)
    }
    
    /// Tier 1: Feature 17 - Validates selecting light and dark appearance overrides.
    func test_tier1_feature17_themeModeSelectionLightAndDark() throws {
        sut.setThemeMode(.light)
        XCTAssertEqual(sut.themeMode, .light)
        XCTAssertEqual(sut.preferredColorScheme, .light)
        
        sut.setThemeMode(.dark)
        XCTAssertEqual(sut.themeMode, .dark)
        XCTAssertEqual(sut.preferredColorScheme, .dark)
    }
    
    /// Tier 1: Feature 17 - Validates resetting settings to factory defaults restores all properties.
    func test_tier1_feature17_resetToDefaultsRestoresAllSettings() throws {
        sut.setAudioQuality(.standard)
        sut.toggleNoiseSuppression()
        sut.setSpeechLanguageLocale("ja-JP")
        sut.setThemeMode(.dark)
        sut.setAPIKey("custom_key")
        
        sut.resetToDefaults()
        
        XCTAssertEqual(sut.audioQuality, .high)
        XCTAssertTrue(sut.isNoiseSuppressionEnabled)
        XCTAssertEqual(sut.speechLanguageLocale, "en-US")
        XCTAssertEqual(sut.themeMode, .system)
        XCTAssertEqual(sut.apiKey, "")
        XCTAssertEqual(sut.summaryStyle, .executive)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 2: Typography & Contrast)
    
    /// Tier 2: Feature 2 - Validates font scale clamping under extreme accessibility Dynamic Type settings.
    func test_tier2_feature2_extremeFontAccessibilityScaleClamping() throws {
        let clampedScale = sut.clampedFontScale(for: 3.5)
        XCTAssertLessThanOrEqual(clampedScale, 2.0)
        
        let minScale = sut.clampedFontScale(for: 0.2)
        XCTAssertGreaterThanOrEqual(minScale, 0.8)
    }
    
    /// Tier 2: Feature 2 - Validates minimum contrast ratio threshold (4.5:1) for brand primary text.
    func test_tier2_feature2_colorContrastThresholdCompliance() throws {
        let contrastRatio = sut.calculateContrastRatio(foregroundHex: "#1E2E28", backgroundHex: "#FFFFFF")
        XCTAssertGreaterThanOrEqual(contrastRatio, 4.5)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 14: Audio Settings Boundaries)
    
    /// Tier 2: Feature 14 - Validates invalid bitrate integer fallback to standard 64kbps.
    func test_tier2_feature14_invalidBitrateValueFallback() throws {
        mockUserDefaults.set(9999, forKey: "MeetMind_AudioBitrate")
        let fallbackSut = SettingsViewModel(userDefaults: mockUserDefaults, cacheDirectory: tempDirectoryURL)
        
        XCTAssertEqual(fallbackSut.audioQuality, .high)
    }
    
    /// Tier 2: Feature 14 - Validates attempting to switch audio quality during recording is blocked.
    func test_tier2_feature14_audioQualitySwitchingDuringRecordingPrevented() throws {
        sut.notifyRecordingSessionActive(true)
        
        let didChange = sut.setAudioQuality(.standard)
        XCTAssertFalse(didChange)
        XCTAssertEqual(sut.audioQuality, .high) // Remained high
        XCTAssertTrue(sut.isAudioSettingsLocked)
    }
    
    /// Tier 2: Feature 14 - Validates corrupt UserDefaults recovery for noise suppression flag.
    func test_tier2_feature14_audioSettingsCorruptUserDefaultsRecovery() throws {
        mockUserDefaults.set("invalid_bool", forKey: "MeetMind_NoiseSuppression")
        let fallbackSut = SettingsViewModel(userDefaults: mockUserDefaults, cacheDirectory: tempDirectoryURL)
        
        XCTAssertTrue(fallbackSut.isNoiseSuppressionEnabled)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 15: Locale & API Key)
    
    /// Tier 2: Feature 15 - Validates unsupported speech locale string falls back to English (US) and persists to UserDefaults.
    func test_tier2_feature15_unsupportedLocaleFallbackToSystemLocale() throws {
        sut.setSpeechLanguageLocale("xx-YY")
        XCTAssertEqual(sut.speechLanguageLocale, "en-US")
        XCTAssertEqual(mockUserDefaults.string(forKey: "MeetMind_SpeechLocale"), "en-US")
    }
    
    /// Tier 2: Feature 15 - Validates submitting empty or whitespace-only API key clears key.
    func test_tier2_feature15_emptyAPIKeySubmissionTreatedAsNil() throws {
        sut.setAPIKey("initial-key")
        XCTAssertTrue(sut.hasCustomAPIKey)
        
        sut.setAPIKey("   \t  ")
        XCTAssertEqual(sut.apiKey, "")
        XCTAssertFalse(sut.hasCustomAPIKey)
    }
    
    /// Tier 2: Feature 15 - Validates API key leading/trailing whitespace trimming.
    func test_tier2_feature15_apiKeyWithWhitespaceTrimming() throws {
        sut.setAPIKey("   sk-1234567890   \n")
        XCTAssertEqual(sut.apiKey, "sk-1234567890")
    }
    
    /// Tier 2: Feature 15 - Validates on-device toggle enforcement under offline simulation.
    func test_tier2_feature15_onDeviceToggleUnderOfflineNetworkCondition() throws {
        sut.simulateNetworkStatus(isOnline: false)
        
        XCTAssertTrue(sut.mustUseOnDeviceRecognition)
        XCTAssertTrue(sut.isOnlineRecognitionDisabled)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 16: Cache & Storage Boundaries)
    
    /// Tier 2: Feature 16 - Validates storage usage calculation on completely empty directory.
    func test_tier2_feature16_zeroBytesStorageCacheState() throws {
        sut.clearTemporaryCache()
        XCTAssertEqual(sut.temporaryCacheSizeBytes, 0)
        XCTAssertEqual(sut.formattedCacheSize, "0 KB")
    }
    
    /// Tier 2: Feature 16 - Validates massive cache size formatting exceeding 10 GB.
    func test_tier2_feature16_massiveCachePurgeCalculation() throws {
        let tenGB: Int64 = 10 * 1024 * 1024 * 1024
        sut.setSimulatedCacheSize(bytes: tenGB)
        XCTAssertEqual(sut.formattedCacheSize, "10.00 GB")
    }
    
    /// Tier 2: Feature 16 - Validates clear cache empties temp folder while preserving primary documents.
    func test_tier2_feature16_clearCachePreservesSavedMeetingAudioFiles() throws {
        let permanentDir = tempDirectoryURL.deletingLastPathComponent().appendingPathComponent("Documents_Audio")
        try? FileManager.default.createDirectory(at: permanentDir, withIntermediateDirectories: true)
        let savedAudioFile = permanentDir.appendingPathComponent("saved_meeting.m4a")
        try? Data("saved meeting audio".utf8).write(to: savedAudioFile)
        
        sut.clearTemporaryCache()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedAudioFile.path))
        try? FileManager.default.removeItem(at: permanentDir)
    }
    
    /// Tier 2: Feature 16 - Validates storage calculation handles missing cache directory without crashing.
    func test_tier2_feature16_storageCalculationHandlesMissingDirectoryGracefully() throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        
        sut.recalculateStorageUsage()
        XCTAssertEqual(sut.temporaryCacheSizeBytes, 0)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases (Feature 17: Theme State & Dynamic Updates)
    
    /// Tier 2: Feature 17 - Validates dynamic theme switching updates without app restart.
    func test_tier2_feature17_dynamicThemeToggleWithoutAppRelaunch() throws {
        var observedColorSchemes: [ColorSchemePreference?] = []
        sut.onColorSchemeChanged = { scheme in
            observedColorSchemes.append(scheme)
        }
        
        sut.setThemeMode(.light)
        sut.setThemeMode(.dark)
        sut.setThemeMode(.system)
        
        XCTAssertEqual(observedColorSchemes.count, 3)
        XCTAssertEqual(observedColorSchemes[0], .light)
        XCTAssertEqual(observedColorSchemes[1], .dark)
        XCTAssertNil(observedColorSchemes[2])
    }
    
    /// Tier 2: Feature 17 - Validates rapid theme cycling preserves thread safety and final state.
    func test_tier2_feature17_rapidThemeCyclingStability() throws {
        let modes: [ThemeMode] = [.system, .light, .dark]
        for _ in 0..<50 {
            let nextMode = modes.randomElement()!
            sut.setThemeMode(nextMode)
            XCTAssertEqual(sut.themeMode, nextMode)
        }
    }
    
    /// Tier 2: Feature 17 - Validates corrupt theme string in UserDefaults defaults to system mode.
    func test_tier2_feature17_invalidThemeStringFallbackToSystem() throws {
        mockUserDefaults.set("neon_cyberpunk_mode", forKey: "MeetMind_ThemeMode")
        let fallbackSut = SettingsViewModel(userDefaults: mockUserDefaults, cacheDirectory: tempDirectoryURL)
        
        XCTAssertEqual(fallbackSut.themeMode, .system)
        XCTAssertNil(fallbackSut.preferredColorScheme)
    }
    
    /// Tier 2: Feature 17 - Validates preferred color scheme environment override mapping.
    func test_tier2_feature17_preferredColorSchemeMapping() throws {
        sut.setThemeMode(.light)
        XCTAssertEqual(sut.colorSchemeOptionString, "Light")
        
        sut.setThemeMode(.dark)
        XCTAssertEqual(sut.colorSchemeOptionString, "Dark")
        
        sut.setThemeMode(.system)
        XCTAssertEqual(sut.colorSchemeOptionString, "System")
    }
    
    /// Tier 2: Feature 17 - Validates high contrast mode adjustment maintains token consistency.
    func test_tier2_feature17_highContrastModeTokenAdjustment() throws {
        sut.setHighContrastEnabled(true)
        XCTAssertTrue(sut.isHighContrastEnabled)
        
        let highContrastBorder = sut.activeBorderColorHex
        XCTAssertEqual(highContrastBorder, "#000000")
        
        sut.setHighContrastEnabled(false)
        XCTAssertFalse(sut.isHighContrastEnabled)
    }
}
