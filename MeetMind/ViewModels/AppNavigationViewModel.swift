import Foundation
import Observation

/// Application root routing container
public enum RootRoute: String, Sendable {
    case onboarding = "onboarding"
    case mainTabs = "mainTabs"
}

/// Primary root tab identifiers
public enum TabIdentifier: String, CaseIterable, Sendable {
    case home = "home"
    case actionItems = "actionItems"
    case search = "search"
}

/// Navigation stack destination targets
public enum NavigationDestination: Hashable, Sendable {
    case meetingDetail(id: UUID)
    case meetingProcessing(id: UUID)
    case liveRecording(id: UUID)
    case settings
}

/// Stage within the onboarding sequence
public enum OnboardingStage: String, Sendable {
    case carousel = "carousel"
    case verifyEmail = "verifyEmail"
    case profileSetup = "profileSetup"
    case permissionsPrimer = "permissionsPrimer"
}

/// Slide content model for onboarding carousel
public struct OnboardingSlide: Identifiable, Sendable, Equatable {
    public let id: Int
    public let title: String
    public let subtitle: String
    public let imageName: String
    
    public init(id: Int, title: String, subtitle: String, imageName: String = "sparkles") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageName = imageName
    }
}

/// Modal sheets presentable from anywhere in the app
public enum AppModal: Identifiable, Sendable {
    case newMeeting
    case editActionItem(id: UUID)
    case exportMinutes
    
    public var id: String {
        switch self {
        case .newMeeting: return "newMeeting"
        case .editActionItem(let id): return "editActionItem_\(id.uuidString)"
        case .exportMinutes: return "exportMinutes"
        }
    }
}

/// ViewModel managing app lifecycle, onboarding carousel, profile baselines, permissions primer, and tabs
@Observable
@MainActor
public final class AppNavigationViewModel {
    public var isOnboardingCompleted: Bool = false
    public var hasCompletedOnboarding: Bool {
        get { isOnboardingCompleted }
        set { isOnboardingCompleted = newValue }
    }
    
    public var rootRoute: RootRoute = .onboarding
    public var currentOnboardingPage: Int = 0
    public var carouselPageIndex: Int {
        get { currentOnboardingPage }
        set { currentOnboardingPage = newValue }
    }
    public var totalOnboardingPages: Int = 3
    public var isLastOnboardingPage: Bool {
        currentOnboardingPage >= totalOnboardingPages - 1
    }
    public var onboardingStage: OnboardingStage = .carousel
    
    public var carouselPages: [OnboardingSlide] = [
        OnboardingSlide(id: 0, title: "Intelligent Meeting Notes", subtitle: "Transform spoken conversations into structured notes automatically."),
        OnboardingSlide(id: 1, title: "Real-Time Speech & Diarization", subtitle: "On-device speech recognition with live speaker attribution."),
        OnboardingSlide(id: 2, title: "Actionable AI Summaries", subtitle: "Instant executive summaries, key decisions, and sync to Apple Reminders.")
    ]
    
    public var selectedTab: TabIdentifier = .home
    public var activeTab: TabIdentifier {
        get { selectedTab }
        set { selectedTab = newValue }
    }
    
    public var navigationPath: [NavigationDestination] = []
    public var actionItemsBadgeCount: Int = 0
    
    public var formattedActionItemsBadge: String? {
        if actionItemsBadgeCount <= 0 {
            return nil
        } else if actionItemsBadgeCount > 99 {
            return "99+"
        } else {
            return "\(actionItemsBadgeCount)"
        }
    }
    
    // Profile State
    public var profileName: String = ""
    public var profileEmail: String = ""
    public var profileRole: String = ""
    
    public var isProfileEmailValid: Bool {
        let trimmed = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
        return predicate.evaluate(with: trimmed)
    }
    
    public var isProfileValidForContinue: Bool {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 100
    }
    
    public var isRecordingVoiceBaseline: Bool = false
    public var hasVoiceBaseline: Bool = false
    public var voiceBaselineURL: URL? = nil
    
    // Permissions State
    public var isMicrophoneAuthorized: Bool = false
    public var isSpeechRecognitionAuthorized: Bool = false
    public var isCalendarAuthorized: Bool = false
    public var canEnterApplication: Bool {
        isMicrophoneAuthorized && isSpeechRecognitionAuthorized
    }
    public var shouldShowSettingsRedirectAlert: Bool = false
    public var permissionStatusDescription: String = "Microphone access is required to record meetings."
    public var hasPartialPermissions: Bool {
        isMicrophoneAuthorized || isSpeechRecognitionAuthorized || isCalendarAuthorized
    }
    public var systemSettingsURL: URL? {
        URL(string: "app-settings:")
    }
    
    public var activeModal: AppModal? = nil
    public var onScrollToTopRequested: (() -> Void)? = nil
    
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        let completed = userDefaults.bool(forKey: "MeetMind_IsOnboardingCompleted")
        self.isOnboardingCompleted = completed
        self.rootRoute = completed ? .mainTabs : .onboarding
    }
    
    public func completeOnboarding() {
        isOnboardingCompleted = true
        rootRoute = .mainTabs
        selectedTab = .home
        userDefaults.set(true, forKey: "MeetMind_IsOnboardingCompleted")
    }
    
    public func pushRoute(_ route: NavigationDestination) {
        navigationPath.append(route)
    }
    
    public func popRoute() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    public func popToRoot() {
        navigationPath.removeAll()
    }
    
    public func handleDeepLink(url: URL) -> Bool {
        guard url.scheme == "meetmind" else { return false }
        guard url.host == "meeting" else { return false }
        
        let pathComponent = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let uuid = UUID(uuidString: pathComponent) else { return false }
        
        selectedTab = .home
        navigationPath.append(.meetingDetail(id: uuid))
        return true
    }
    
    public func nextOnboardingPage() {
        if currentOnboardingPage < totalOnboardingPages - 1 {
            currentOnboardingPage += 1
        }
    }
    
    public func previousOnboardingPage() {
        if currentOnboardingPage > 0 {
            currentOnboardingPage -= 1
        }
    }
    
    
    
    public func skipOnboardingCarousel() {
        onboardingStage = .profileSetup
    }
    
    public func skipOnboarding() {
        completeOnboarding()
    }
    
    public func setOnboardingPage(_ page: Int) {
        currentOnboardingPage = max(0, min(totalOnboardingPages - 1, page))
    }
    
    public func updateProfile(name: String, email: String, role: String) {
        let clampedName = String(name.prefix(100))
        self.profileName = clampedName
        self.profileEmail = email
        self.profileRole = role
    }
    
    public func startVoiceBaselineRecording() {
        isRecordingVoiceBaseline = true
    }
    
    public func stopVoiceBaselineRecording(sampleURL: URL) {
        isRecordingVoiceBaseline = false
        hasVoiceBaseline = true
        voiceBaselineURL = sampleURL
    }
    
    public func saveVoiceBaseline(url: URL) {
        hasVoiceBaseline = true
        voiceBaselineURL = url
    }
    
    public func deleteVoiceBaseline() {
        hasVoiceBaseline = false
        voiceBaselineURL = nil
    }
    
    public func skipVoiceBaseline() {
        hasVoiceBaseline = false
        voiceBaselineURL = nil
    }
    
    public func advanceFromProfileToPermissions() {
        onboardingStage = .permissionsPrimer
    }
    
    public func setMicrophonePermission(authorized: Bool) {
        isMicrophoneAuthorized = authorized
    }
    
    public func setSpeechRecognitionPermission(authorized: Bool) {
        isSpeechRecognitionAuthorized = authorized
    }
    
    public func setCalendarPermission(authorized: Bool) {
        isCalendarAuthorized = authorized
    }
    
    public func setMicrophonePermissionDeniedByUser(_ denied: Bool) {
        shouldShowSettingsRedirectAlert = denied
        if denied {
            permissionStatusDescription = "Microphone access is required to record meetings."
        }
    }
    
    public func finishPermissionsPrimer() {
        completeOnboarding()
    }
    
    public func selectTab(_ tab: TabIdentifier) {
        selectedTab = tab
    }
    
    public func updateActionItemsBadgeCount(_ count: Int) {
        actionItemsBadgeCount = max(0, count)
    }
    
    public func handleTabReselection(tab: TabIdentifier) {
        if selectedTab == tab {
            onScrollToTopRequested?()
        }
    }
    
    
}

// MARK: - Compatibility Extensions for E2E Test Suite (OnboardingAndSettingsE2ETests)
extension AppNavigationViewModel {
    public var userProfile: UserProfile? {
        get {
            guard !profileName.isEmpty || isOnboardingCompleted else { return nil }
            return UserProfile(
                name: profileName.isEmpty ? "MeetMind User" : profileName,
                email: profileEmail,
                role: profileRole,
                avatarColorHex: "#3B82F6",
                voiceProfileURL: voiceBaselineURL,
                isCalendarSyncEnabled: isCalendarAuthorized
            )
        }
        set {
            if let newValue {
                profileName = newValue.name
                profileEmail = newValue.email
                profileRole = newValue.role
                voiceBaselineURL = newValue.voiceProfileURL
                hasVoiceBaseline = (newValue.voiceProfileURL != nil)
            } else {
                profileName = ""
                profileEmail = ""
                profileRole = ""
                voiceBaselineURL = nil
                hasVoiceBaseline = false
            }
        }
    }
    
    public var selectedTabIndex: Int {
        get {
            switch selectedTab {
            case .home: return 0
            case .actionItems: return 1
            case .search: return 2
            }
        }
        set {
            switch newValue {
            case 0: selectedTab = .home
            case 1: selectedTab = .actionItems
            case 2: selectedTab = .search
            // Index 3 was the removed Settings tab. Old snapshots restore safely to Meetings.
            case 3: selectedTab = .home
            default: selectedTab = .home
            }
        }
    }
    
    public var presentedMeetingDetailID: UUID? {
        get {
            for destination in navigationPath.reversed() {
                if case .meetingDetail(let id) = destination {
                    return id
                }
            }
            return nil
        }
        set {
            if let newValue {
                navigationPath.append(.meetingDetail(id: newValue))
            }
        }
    }
    
    public func setupProfile(name: String, email: String, role: String, voiceSampleURL: URL? = nil) {
        updateProfile(name: name, email: email, role: role)
        if let voiceSampleURL {
            saveVoiceBaseline(url: voiceSampleURL)
        }
    }
    
    public func skipProfileSetup() {
        setupProfile(name: "MeetMind User", email: "", role: "", voiceSampleURL: nil)
        completeOnboarding()
    }
    
    
    public func isPermissionGranted(_ type: PermissionType) -> Bool {
        switch type {
        case .microphone: return isMicrophoneAuthorized
        case .speechRecognition: return isSpeechRecognitionAuthorized
        case .calendar, .reminders, .notifications: return isCalendarAuthorized
        }
    }
    
    
    
    public func settingsDeepLinkURL() -> URL {
        systemSettingsURL ?? (URL(string: "app-settings:") ?? URL(fileURLWithPath: "/"))
    }
    
    public func navigateToMeetingDetail(meetingID: UUID) {
        pushRoute(.meetingDetail(id: meetingID))
    }
    
    public func createRestorationSnapshot() -> NavigationRestorationSnapshot {
        NavigationRestorationSnapshot(
            selectedTabIndex: selectedTabIndex,
            presentedMeetingDetailID: presentedMeetingDetailID,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }
    
    public func restore(from snapshot: NavigationRestorationSnapshot) {
        selectedTabIndex = snapshot.selectedTabIndex
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        isOnboardingCompleted = snapshot.hasCompletedOnboarding
        rootRoute = snapshot.hasCompletedOnboarding ? .mainTabs : .onboarding
        if snapshot.selectedTabIndex == 3 {
            navigationPath.removeAll()
        } else if let detailID = snapshot.presentedMeetingDetailID {
            navigateToMeetingDetail(meetingID: detailID)
        }
    }
}
