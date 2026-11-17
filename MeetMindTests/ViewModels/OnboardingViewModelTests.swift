//
//  OnboardingViewModelTests.swift
//  MeetMindTests
//
//  Created by MeetMind Test Automation.
//

import XCTest
import Foundation
@testable import MeetMind

/// Comprehensive unit test suite covering OnboardingViewModel:
/// Carousel progression, profile validation, voice baseline recording, permissions priming, and completion.
@MainActor
final class OnboardingViewModelTests: XCTestCase {
    
    private var mockPermissions: MockPermissionsService!
    private var sut: OnboardingViewModel!
    
    override func setUp() {
        super.setUp()
        mockPermissions = MockPermissionsService()
        sut = OnboardingViewModel(permissionsService: mockPermissions)
    }
    
    override func tearDown() {
        sut = nil
        mockPermissions = nil
        super.tearDown()
    }
    
    // MARK: - Carousel Tests
    
    func test_initialCarouselState() {
        XCTAssertEqual(sut.currentStage, .carousel)
        XCTAssertEqual(sut.currentSlideIndex, 0)
        XCTAssertEqual(sut.totalSlides, 3)
        XCTAssertEqual(sut.slides.count, 3)
        XCTAssertFalse(sut.isOnboardingCompleted)
    }
    
    func test_advanceSlideAcrossAllPages() {
        XCTAssertEqual(sut.currentSlideIndex, 0)
        sut.advanceSlide()
        XCTAssertEqual(sut.currentSlideIndex, 1)
        sut.advanceSlide()
        XCTAssertEqual(sut.currentSlideIndex, 2)
        
        // Advancing from final slide transitions to profileSetup stage
        sut.advanceSlide()
        XCTAssertEqual(sut.currentStage, .profileSetup)
    }
    
    func test_regressSlideBoundaries() {
        sut.regressSlide()
        XCTAssertEqual(sut.currentSlideIndex, 0)
        
        sut.advanceSlide()
        sut.advanceSlide()
        XCTAssertEqual(sut.currentSlideIndex, 2)
        
        sut.regressSlide()
        XCTAssertEqual(sut.currentSlideIndex, 1)
        sut.regressSlide()
        XCTAssertEqual(sut.currentSlideIndex, 0)
    }
    
    func test_skipCarouselTransitionsToProfileSetup() {
        sut.skipCarousel()
        XCTAssertEqual(sut.currentStage, .profileSetup)
        XCTAssertEqual(sut.currentSlideIndex, 2)
    }
    
    // MARK: - Profile Setup & Validation Tests
    
    func test_profileNameValidation() {
        sut.name = ""
        XCTAssertFalse(sut.isNameValid)
        
        sut.name = " "
        XCTAssertFalse(sut.isNameValid)
        
        sut.name = "A"
        XCTAssertFalse(sut.isNameValid)
        
        sut.name = "Al"
        XCTAssertTrue(sut.isNameValid)
        
        sut.name = "Alice Smith"
        XCTAssertTrue(sut.isNameValid)
        
        sut.name = String(repeating: "A", count: 101)
        XCTAssertFalse(sut.isNameValid)
    }
    
    func test_profileEmailValidation() {
        sut.email = ""
        XCTAssertTrue(sut.isEmailValid) // Optional email is valid when empty
        
        sut.email = "alice@example.com"
        XCTAssertTrue(sut.isEmailValid)
        
        sut.email = "invalid-email"
        XCTAssertFalse(sut.isEmailValid)
    }
    
    func test_canProceedFromProfile() {
        sut.name = ""
        sut.email = ""
        XCTAssertFalse(sut.canProceedFromProfile)
        
        sut.name = "Bob"
        sut.email = "not-an-email"
        XCTAssertFalse(sut.canProceedFromProfile)
        
        sut.name = "Bob"
        sut.email = "bob@example.com"
        XCTAssertTrue(sut.canProceedFromProfile)
        
        sut.saveProfileAndContinue()
        XCTAssertEqual(sut.currentStage, .permissionsPrimer)
    }
    
    func test_skipProfileSetupAppliesDefaults() {
        sut.skipProfileSetup()
        XCTAssertEqual(sut.currentStage, .permissionsPrimer)
        XCTAssertEqual(sut.currentUserProfile.name, "MeetMind User")
        XCTAssertEqual(sut.currentUserProfile.role, "Team Member")
        XCTAssertNil(sut.currentUserProfile.voiceProfileURL)
    }
    
    func test_avatarColorPresetsSelection() {
        XCTAssertEqual(sut.avatarColorPresets.count, 6)
        sut.selectedAvatarColorHex = "#8B5CF6"
        XCTAssertEqual(sut.currentUserProfile.avatarColorHex, "#8B5CF6")
    }
    
    func test_voiceBaselineRecordingCycle() {
        XCTAssertFalse(sut.hasVoiceBaseline)
        XCTAssertFalse(sut.isRecordingVoiceBaseline)
        
        sut.startVoiceBaselineRecording()
        XCTAssertTrue(sut.isRecordingVoiceBaseline)
        
        let sampleURL = URL(fileURLWithPath: "/tmp/sample.m4a")
        sut.stopVoiceBaselineRecording(sampleURL: sampleURL)
        XCTAssertFalse(sut.isRecordingVoiceBaseline)
        XCTAssertTrue(sut.hasVoiceBaseline)
        XCTAssertEqual(sut.voiceProfileURL, sampleURL)
        
        sut.skipVoiceBaseline()
        XCTAssertFalse(sut.hasVoiceBaseline)
        XCTAssertNil(sut.voiceProfileURL)
    }
    
    // MARK: - Permissions Primer Tests
    
    func test_permissionStatusLookup() {
        mockPermissions.setStatus(.authorized, for: .microphone)
        mockPermissions.setStatus(.denied, for: .speechRecognition)
        sut.refreshPermissions()
        
        XCTAssertTrue(sut.isPermissionGranted(for: .microphone))
        XCTAssertFalse(sut.isPermissionGranted(for: .speechRecognition))
        XCTAssertEqual(sut.permissionStatus(for: .microphone), .authorized)
        XCTAssertEqual(sut.permissionStatus(for: .speechRecognition), .denied)
    }
    
    func test_requestPermissionGrantsAccess() async {
        mockPermissions.setStatus(.notDetermined, for: .microphone)
        let status = await sut.requestPermission(.microphone)
        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(sut.isPermissionGranted(for: .microphone))
        XCTAssertFalse(sut.shouldShowSettingsAlert)
    }
    
    func test_requestPermissionFromNilStatusGrantsAccess() async {
        let freshMock = MockPermissionsService()
        let vm = OnboardingViewModel(permissionsService: freshMock)
        let status = await vm.requestPermission(.speechRecognition)
        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(vm.isPermissionGranted(for: .speechRecognition))
        XCTAssertFalse(vm.shouldShowSettingsAlert)
    }
    
    func test_requestPermissionDeniedSetsAlert() async {
        mockPermissions.setStatus(.denied, for: .microphone)
        let status = await sut.requestPermission(.microphone)
        XCTAssertEqual(status, .denied)
        XCTAssertFalse(sut.isPermissionGranted(for: .microphone))
        XCTAssertTrue(sut.shouldShowSettingsAlert)
        XCTAssertEqual(sut.lastDeniedPermission, .microphone)
    }
    
    func test_requestAllPermissions() async {
        await sut.requestAllPermissions()
        XCTAssertTrue(sut.isPermissionGranted(for: .microphone))
        XCTAssertTrue(sut.isPermissionGranted(for: .speechRecognition))
        XCTAssertTrue(sut.isPermissionGranted(for: .calendar))
        XCTAssertTrue(sut.isPermissionGranted(for: .reminders))
    }
    
    func test_completeOnboardingFiresCallback() {
        var completedProfile: UserProfile? = nil
        sut.onCompletion = { profile in
            completedProfile = profile
        }
        
        sut.name = "Ada Lovelace"
        sut.email = "ada@computing.org"
        sut.role = "Analyst"
        sut.completeOnboarding()
        
        XCTAssertTrue(sut.isOnboardingCompleted)
        XCTAssertNotNil(completedProfile)
        XCTAssertEqual(completedProfile?.name, "Ada Lovelace")
        XCTAssertEqual(completedProfile?.email, "ada@computing.org")
        XCTAssertEqual(completedProfile?.role, "Analyst")
    }
}
