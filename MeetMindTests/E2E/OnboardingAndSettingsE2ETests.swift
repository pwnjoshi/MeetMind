import XCTest
import Foundation
import SwiftData
@testable import MeetMind

@MainActor
final class OnboardingAndSettingsE2ETests: XCTestCase {
    func testLocalOnboardingRequiresNoAccount() {
        let onboarding = OnboardingViewModel(permissionsService: MockPermissionsService())
        onboarding.name = "  Alex  "
        onboarding.continueLocally()
        XCTAssertEqual(onboarding.currentStage, .permissionsPrimer)
        XCTAssertEqual(onboarding.name, "Alex")
        XCTAssertTrue(onboarding.email.isEmpty)
        var profile: UserProfile?
        onboarding.onCompletion = { profile = $0 }
        onboarding.completeOnboarding()
        XCTAssertEqual(profile?.name, "Alex")
    }
    func testOnDeviceSpeechPreferenceSurvivesRelaunch() throws {
        let suite = "MeetMindTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsViewModel(userDefaults: defaults)
        XCTAssertTrue(settings.isOnDeviceRecognitionOnly)
        settings.isOnDeviceRecognitionOnly = false
        XCTAssertFalse(SettingsViewModel(userDefaults: defaults).isOnDeviceRecognitionOnly)
    }
}
