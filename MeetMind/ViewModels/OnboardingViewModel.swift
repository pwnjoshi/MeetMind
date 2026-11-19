import Foundation
import Observation

/// ViewModel managing onboarding carousel, profile configuration, voice baseline, and permissions priming
@Observable
@MainActor
public final class OnboardingViewModel {
    public let permissionsService: PermissionsServiceProtocol
    
    // MARK: - Navigation & Stage State
    public var currentStage: OnboardingStage = .carousel
    public var currentSlideIndex: Int = 0
    public let totalSlides: Int = 3
    public var isOnboardingCompleted: Bool = false
    
    // MARK: - Carousel Slides Content
    public let slides: [OnboardingSlide] = [
        OnboardingSlide(
            id: 0,
            title: "Record Every Meeting",
            subtitle: "One tap captures the whole conversation, even without internet.",
            imageName: "waveform.badge.mic"
        ),
        OnboardingSlide(
            id: 1,
            title: "Minutes Write Themselves",
            subtitle: "Decisions, actions and owners, ready the moment you stop.",
            imageName: "doc.text.fill"
        ),
        OnboardingSlide(
            id: 2,
            title: "Ask Vidur Anything",
            subtitle: "Find what was said or decided. Your recordings stay on this iPhone.",
            imageName: "sparkles"
        )
    ]
    
    // MARK: - User Profile Form State
    public var name: String = ""
    public var email: String = ""
    public var role: String = ""
    public var selectedAvatarColorHex: String = "#3B82F6"
    public var voiceProfileURL: URL? = nil
    public var isCalendarSyncEnabled: Bool = false
    
    public let avatarColorPresets: [String] = [
        "#3B82F6", // Live Blue
        "#8B5CF6", // AI Purple
        "#10B981", // Mint Green
        "#F59E0B", // Warm Amber
        "#EF4444", // Coral Red
        "#1E2E28"  // Primary Slate
    ]
    
    // MARK: - Voice Baseline Recording State
    public var isRecordingVoiceBaseline: Bool = false
    public var voiceBaselineDuration: TimeInterval = 0.0
    public var hasVoiceBaseline: Bool = false
    
    // MARK: - Sign In & Verification State
    public var enteredEmail: String = ""
    public var verificationDigits: [String] = Array(repeating: "", count: 6)
    public var isResendCodeConfirmationShown: Bool = false
    
    public func continueWithEmail() {
        email = enteredEmail
        currentStage = .verifyEmail
    }
    
    public func continueWithSocialAuth(provider: String) {
        continueLocally()
    }
    
    public func verifyCodeAndContinue() {
        continueLocally()
    }

    public func continueLocally() {
        name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        if name.isEmpty { name = "Manent User" }
        email = ""
        role = ""
        currentStage = .permissionsPrimer
    }
    
    public func backToSignIn() {
        currentStage = .carousel
    }
    
    // MARK: - Permissions Primer State
    public var shouldShowSettingsAlert: Bool = false
    public var lastDeniedPermission: PermissionType? = nil
    public var permissionStatuses: [PermissionType: PermissionStatus] = [:]
    
    // MARK: - Completion Callback
    public var onCompletion: ((UserProfile) -> Void)? = nil
    
    // MARK: - Initializer
    public init(
        permissionsService: PermissionsServiceProtocol = SystemPermissionsService(),
        onCompletion: ((UserProfile) -> Void)? = nil
    ) {
        self.permissionsService = permissionsService
        self.onCompletion = onCompletion
        for p in PermissionType.allCases {
            self.permissionStatuses[p] = permissionsService.status(for: p)
        }
    }
    
    // MARK: - Computed Properties & Validations
    public var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 100
    }
    
    public var isEmailValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
    
    public var canProceedFromProfile: Bool {
        isNameValid && isEmailValid
    }
    
    public var currentUserProfile: UserProfile {
        UserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Manent User" : name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarColorHex: selectedAvatarColorHex,
            voiceProfileURL: voiceProfileURL,
            isCalendarSyncEnabled: isCalendarSyncEnabled
        )
    }
    
    // MARK: - Carousel Navigation
    public func advanceSlide() {
        if currentSlideIndex < totalSlides - 1 {
            currentSlideIndex += 1
        } else {
            // The next screen preserves the Figma sign-in composition but offers
            // only local entry; profile details remain editable from Settings.
            currentStage = .verifyEmail
        }
    }
    
    public func regressSlide() {
        if currentSlideIndex > 0 {
            currentSlideIndex -= 1
        }
    }
    
    public func skipCarousel() {
        currentSlideIndex = totalSlides - 1
        currentStage = .verifyEmail
    }
    
    // MARK: - Profile Actions
    public func saveProfileAndContinue() {
        guard canProceedFromProfile else { return }
        currentStage = .permissionsPrimer
    }
    
    public func skipProfileSetup() {
        name = "Manent User"
        role = "Team Member"
        email = ""
        voiceProfileURL = nil
        hasVoiceBaseline = false
        currentStage = .permissionsPrimer
    }
    
    // MARK: - Voice Baseline Actions
    public func startVoiceBaselineRecording() {
        isRecordingVoiceBaseline = true
        voiceBaselineDuration = 0.0
    }
    
    public func stopVoiceBaselineRecording(sampleURL: URL? = nil) {
        isRecordingVoiceBaseline = false
        let destination = sampleURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice_baseline_\(UUID().uuidString).m4a")
        voiceProfileURL = destination
        hasVoiceBaseline = true
    }
    
    public func skipVoiceBaseline() {
        isRecordingVoiceBaseline = false
        voiceProfileURL = nil
        hasVoiceBaseline = false
    }
    
    // MARK: - Permissions Operations
    public func permissionStatus(for permission: PermissionType) -> PermissionStatus {
        permissionStatuses[permission] ?? permissionsService.status(for: permission)
    }
    
    public func isPermissionGranted(for permission: PermissionType) -> Bool {
        permissionStatus(for: permission).isGranted
    }
    
    public func refreshPermissions() {
        for p in PermissionType.allCases {
            permissionStatuses[p] = permissionsService.status(for: p)
        }
    }
    
    @discardableResult
    public func requestPermission(_ permission: PermissionType) async -> PermissionStatus {
        let status = await permissionsService.requestPermission(for: permission)
        permissionStatuses[permission] = status
        if status == .denied {
            lastDeniedPermission = permission
            shouldShowSettingsAlert = true
        }
        return status
    }
    
    public func requestAllPermissions() async {
        let results = await permissionsService.requestAllPermissions()
        for (p, status) in results {
            permissionStatuses[p] = status
        }
    }
    
    public var settingsDeepLinkURL: URL? {
        permissionsService.settingsURL
    }
    
    // MARK: - Flow Completion
    public func completeOnboarding() {
        isOnboardingCompleted = true
        onCompletion?(currentUserProfile)
    }
}
