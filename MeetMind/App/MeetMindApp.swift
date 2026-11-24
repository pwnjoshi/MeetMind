import SwiftUI
import SwiftData
import OSLog
import Darwin
import UIKit
import UserNotifications
import OfflineEngineKit

final class MeetMindAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @Published private(set) var completedMeetingID: UUID?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OfflineAnalysisBackgroundScheduler.register()
        UNUserNotificationCenter.current().delegate = self
        trackGPUAvailability(launchedInBackground: application.applicationState == .background)
        return true
    }

    /// iOS rejects GPU work from a backgrounded iPhone app, so on-device models switch
    /// to the CPU and Neural Engine while the app is in the background.
    private func trackGPUAvailability(launchedInBackground: Bool) {
        ComputeEnvironment.setGPUAvailable(!launchedInBackground)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            ComputeEnvironment.setGPUAvailable(false)
        }
        for name in [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                ComputeEnvironment.setGPUAvailable(true)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let value = response.notification.request.content.userInfo["analysisMeetingID"] as? String,
              let id = UUID(uuidString: value) else { return }
        await MainActor.run { completedMeetingID = id }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.userInfo["analysisMeetingID"] == nil ? [] : [.banner, .list, .sound]
    }
}

@main
struct MeetMindApp: App {
    @UIApplicationDelegateAdaptor(MeetMindAppDelegate.self) private var appDelegate
    @State private var container: ModelContainer?
    @State private var startupError: String?
    @State private var deletionRecoveryComplete: Bool
    @State private var deletionRecoveryError: String?
    @State private var appState: AppState
    @State private var router: NavigationRouter
    @State private var settingsVM: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let initializedContainer: ModelContainer?
        var initializationError: String?
        do {
            initializedContainer = try ModelContainerFactory.createProductionContainer()
        } catch {
            Logger(subsystem: "com.meetmind.app", category: "Persistence").error("Store initialization failed: \(String(describing: error), privacy: .public)")
            initializedContainer = nil
            initializationError = error.localizedDescription
        }
        _container = State(initialValue: initializedContainer)
        _startupError = State(initialValue: initializationError)
        let deletionJournal = UserContentInventory.live().journalURL
        _deletionRecoveryComplete = State(initialValue: !FileManager.default.fileExists(atPath: deletionJournal.path))
        _deletionRecoveryError = State(initialValue: nil)
        
        let state = AppState()
        let navRouter = NavigationRouter()
        let settings = SettingsViewModel()
        
        _appState = State(initialValue: state)
        _router = State(initialValue: navRouter)
        _settingsVM = State(initialValue: settings)
        if ProcessInfo.processInfo.arguments.contains("--diagnose-storage") {
            // Content-free verification of the actual production store open.
            let commit = Bundle.main.object(forInfoDictionaryKey: "ManentBuildCommit") as? String ?? "unknown"
            print("MEETMIND_STORAGE_READY \(initializedContainer != nil) commit=\(commit)")
            fflush(stdout)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    Group {
                        if !deletionRecoveryComplete {
                            VStack(spacing: 16) {
                                if let deletionRecoveryError {
                                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                                    Text("Local data erasure is incomplete").font(.title2)
                                    Text(deletionRecoveryError).font(.caption).multilineTextAlignment(.center)
                                    Button("Retry Erasure") { Task { await resumeDeletion(using: container) } }
                                        .buttonStyle(.borderedProminent)
                                } else {
                                    ProgressView("Finishing local data erasure…")
                                }
                            }
                            .padding()
                        } else if ProcessInfo.processInfo.arguments.contains("--offline-benchmark") {
                            NavigationStack { OfflineBenchmarkView() }
                        } else if ProcessInfo.processInfo.arguments.contains("--offline-pipeline-smoke") {
                            OfflinePipelineSmokeView()
                        } else if ProcessInfo.processInfo.arguments.contains("--offline-hindi-smoke") {
                            HindiPipelineSmokeView()
                        } else if ProcessInfo.processInfo.arguments.contains("--offline-evaluation") {
                            EvaluationRunView()
                        } else {
                            appContent
                        }
                    }
                    .modelContainer(container)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.largeTitle)
                        Text("Unable to open your meetings").font(.title2)
                        Text("Your saved data has been kept. Retry opening it, or share the error below for support.")
                        Text(startupError ?? "Unknown storage error")
                            .font(.caption).textSelection(.enabled)
                        Button("Retry") {
                            do {
                                container = try ModelContainerFactory.createProductionContainer()
                                startupError = nil
                            } catch {
                                startupError = error.localizedDescription
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
                .task(id: container != nil) {
                    guard let container else {
                        OfflineAnalysisBackgroundScheduler.useApplicationContainer(nil)
                        return
                    }
                    await resumeDeletion(using: container)
                    if deletionRecoveryComplete {
                        OfflineAnalysisBackgroundScheduler.useApplicationContainer(container)
                    }
                }
                .environment(appState)
                .environment(router)
                .environment(settingsVM)
                .onOpenURL { url in
                    _ = router.handleDeepLink(url: url, appState: appState)
                }
                .onReceive(appDelegate.$completedMeetingID.compactMap { $0 }) { id in
                    guard let container else { return }
                    let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
                    guard let count = try? container.mainContext.fetchCount(descriptor), count > 0 else { return }
                    appState.activeTab = .home
                    router.homePath = [.meetingDetail(id: id)]
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                settingsVM.recalculateStorageUsage()
                if let container {
                    // Repeating meetings: create the next scheduled occurrence once it is due.
                    _ = try? MeetingOccurrenceScheduler.generateDueOccurrences(context: container.mainContext)
                    // Clears minutes topics that earlier versions copied into later series meetings.
                    PlannedAgenda.repairCopiedAgendas(context: container.mainContext)
                    if AnalysisCoordinator.needsPromptExampleRepair {
                        AnalysisCoordinator(context: container.mainContext).repairPromptExampleLeaks()
                    }
                }
            case .background:
                if container != nil, appState.hasCompletedOnboarding {
                    OfflineAnalysisBackgroundScheduler.scheduleInitialSetup()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func resumeDeletion(using container: ModelContainer) async {
        deletionRecoveryError = nil
        do {
            _ = try await DeletionCoordinator(modelContext: container.mainContext).resumePendingDeletionIfNeeded()
            deletionRecoveryComplete = true
        } catch {
            deletionRecoveryComplete = false
            deletionRecoveryError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var appContent: some View {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-profile-long") {
            profileVisualFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-home-populated") {
            homeVisualFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-meeting-review") {
            meetingVisualFixture(.review)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-meeting-draft") {
            meetingVisualFixture(.draft)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-meeting-finalized") {
            meetingVisualFixture(.finalized)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-minutes-sent") {
            MinutesSentFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-recording-finish") {
            recordingVisualFixture(paused: true, showsFinishConfirmation: true)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-recording-paused") {
            recordingVisualFixture(paused: true)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-recording-active") {
            recordingVisualFixture(paused: false)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

    #if targetEnvironment(simulator)
    private struct ProfileVisualFixture {
        let store: ModelContainer
        let settings: SettingsViewModel
        let defaults: UserDefaults
    }

    @MainActor private static var profileFixture: ProfileVisualFixture?

    @MainActor private func profileVisualFixture() -> some View {
        let fixture = Self.profileFixture ?? Self.createProfileFixture()
        Self.profileFixture = fixture
        return NavigationStack {
            SettingsView(fixtureStatistics: ProfileStatistics(
                meetings: "12,345",
                recorded: "987 h",
                openActions: "4,567"
            ))
        }
        .modelContainer(fixture.store)
        .defaultAppStorage(fixture.defaults)
        .environment(AppState(userDefaults: fixture.defaults))
        .environment(NavigationRouter())
        .environment(fixture.settings)
    }

    @MainActor private static func createProfileFixture() -> ProfileVisualFixture {
        let store = try! ModelContainerFactory.createInMemoryContainer()
        let suiteName = "Manent.ProfileVisualFixture"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            "International Institute for Human-Centred Product Engineering",
            forKey: OrganizationProfileStore.nameKey
        )
        let settings = SettingsViewModel(userDefaults: defaults)
        settings.saveUserProfile(UserProfile(
            name: "Dr. Chandrashekhar Venkataraman",
            email: "chandrashekhar.venkataraman@example.com",
            role: "Senior Director of Product Design and Applied Intelligence",
            avatarColorHex: "#5E5CE6"
        ))
        return ProfileVisualFixture(store: store, settings: settings, defaults: defaults)
    }

    @MainActor private static var homeFixtureStore: ModelContainer?

    @MainActor private func homeVisualFixture() -> some View {
        let store = Self.homeFixtureStore ?? Self.createHomeFixture()
        Self.homeFixtureStore = store
        return NavigationStack { HomeDashboardView(modelContext: store.mainContext) }
            .modelContainer(store)
            .environment(AppState(userDefaults: UserDefaults(suiteName: "Manent.HomeFixture") ?? .standard))
            .environment(NavigationRouter())
            .environment(SettingsViewModel(userDefaults: UserDefaults(suiteName: "Manent.HomeFixture") ?? .standard))
    }

    @MainActor private static func createHomeFixture() -> ModelContainer {
        let store = try! ModelContainerFactory.createInMemoryContainer()
        let now = Date()
        let people = [
            Speaker(name: "Maya Rao", avatarColorHex: "#FF9500"),
            Speaker(name: "Arjun Mehta", avatarColorHex: "#34C759"),
            Speaker(name: "Pawan Joshi", avatarColorHex: "#3B82F6"),
            Speaker(name: "Neha Singh", avatarColorHex: "#8E8E93")
        ]
        people.forEach { store.mainContext.insert($0) }
        func add(_ title: String, day: Double, hour: Double, status: MeetingStatus, duration: TimeInterval = 0) -> Meeting {
            let date = now.addingTimeInterval(day * 86_400 + hour * 3_600)
            let meeting = Meeting(title: title, createdAt: date, scheduledStartTime: status == .scheduled ? date : nil,
                                  duration: duration, status: status)
            store.mainContext.insert(meeting)
            people.forEach { meeting.addParticipant($0) }
            return meeting
        }
        let next = add("Design review", day: 0, hour: 0.5, status: .scheduled, duration: 2_700)
        next.seriesID = UUID(); next.seriesName = "Design review"
        let repeatMeeting = add("Design review", day: -7, hour: 0.5, status: .completed, duration: 2_280)
        repeatMeeting.seriesID = next.seriesID; repeatMeeting.seriesName = next.seriesName
        _ = add("Launch readiness", day: 1, hour: 2, status: .scheduled)
        _ = add("Finance review", day: 2, hour: 3, status: .scheduled)
        _ = add("Product planning", day: 4, hour: 1, status: .scheduled)
        _ = add("Finance review", day: -1, hour: 0, status: .completed, duration: 2_520)
        let review = add("Product planning", day: -3, hour: 0, status: .processing, duration: 1_920)
        review.analysisState = "speakerReview"
        let actions = add("October planning", day: -30, hour: 0, status: .completed, duration: 3_000)
        actions.addActionItem(ActionItem(title: "Send estimate", meeting: actions))
        actions.addActionItem(ActionItem(title: "Confirm launch date", meeting: actions))
        try! store.mainContext.save()
        return store
    }

    private enum MeetingFixtureState: Hashable { case review, draft, finalized }

    @MainActor private static var fixtureStores: [MeetingFixtureState: (ModelContainer, UUID)] = [:]

    @MainActor private func meetingVisualFixture(_ state: MeetingFixtureState) -> some View {
        let (store, meetingID) = Self.fixtureStores[state] ?? Self.createMeetingFixture(state)
        return NavigationStack { MeetingDetailContainerView(meetingId: meetingID) }
            .modelContainer(store)
    }

    @MainActor private static func createMeetingFixture(_ state: MeetingFixtureState) -> (ModelContainer, UUID) {
        // An isolated store lets the smoke run exercise the production detail router.
        let store = try! ModelContainerFactory.createInMemoryContainer()
        let meeting = Meeting(title: "October planning", createdAt: Date(timeIntervalSince1970: 1791979200),
                              duration: 948, status: state == .review ? .processing : .completed)
        store.mainContext.insert(meeting)
        meeting.seriesID = UUID()
        meeting.seriesName = "Product planning"
        for (name, color) in [("Sachin Ghai", "#22AFC4"), ("Pawan Joshi", "#FF9500"),
                              ("Vaishnavi Shukla", "#FF2D55"), ("Garima Pant", "#AF52DE")] {
            meeting.addParticipant(Speaker(name: name, avatarColorHex: color))
        }
        let absent = Speaker(name: "Aaditya Uniyal", avatarColorHex: "#34C759")
        meeting.addParticipant(absent)
        meeting.absentParticipantIDs = [absent.id]
        if state != .review {
            meeting.agendaText = "Launch timing and budget"
            if let speaker = meeting.participants.first {
                let segment = TranscriptSegment(text: "The team proposed 20 November for launch.",
                                                startTime: 18, endTime: 23, speaker: speaker)
                store.mainContext.insert(segment)
                meeting.addTranscriptSegment(segment)
            }
            let summary = Summary(executiveSummary: "Launch timing and budget",
                                      keyPoints: ["The team proposed 20 November for launch.", "A budget of about ₹12 lakh was discussed.", "Finance follow-up remained open."],
                                      keyDecisions: ["Budget approval awaits the Finance estimate."])
            store.mainContext.insert(summary)
            meeting.summary = summary
            meeting.minutesNeedFinalization = state == .draft
        } else {
            meeting.analysisState = "speakerReview"
        }
        try! store.mainContext.save()
        let fixture = (store, meeting.id)
        fixtureStores[state] = fixture
        return fixture
    }

    private func recordingVisualFixture(paused: Bool, showsFinishConfirmation: Bool = false) -> some View {
        let meeting = Meeting(title: "Quick meeting", createdAt: Date(), duration: 948, status: .recording)
        let viewModel = LiveRecordingViewModel(meeting: meeting, updatesFromRecordingClock: false)
        viewModel.recordingState = paused ? .paused : .recording
        viewModel.elapsedDuration = 948
        viewModel.waveformLevels = [0.18, 0.42, 0.24, 0.54, 0.31, 0.66, 0.38, 0.51,
                                    0.28, 0.73, 0.34, 0.61, 0.44, 0.69, 0.32, 0.57,
                                    0.41, 0.77, 0.36, 0.62, 0.29, 0.70, 0.45, 0.58,
                                    0.33, 0.67, 0.39, 0.74, 0.30, 0.55, 0.43, 0.64]
        viewModel.finalTranscriptSegments = [
            LiveTranscriptSegmentItem(speakerName: "Speaker 2",
                                      text: "I’ll update the launch checklist.",
                                      startTime: 730, endTime: 735),
            LiveTranscriptSegmentItem(speakerName: "Speaker 3",
                                      text: "We need a Finance estimate before approving the budget.",
                                      startTime: 882, endTime: 890)
        ]
        viewModel.isBookmarkButtonHighlighted = paused
        return NavigationStack {
            LiveRecordingView(
                meetingId: meeting.id,
                viewModel: viewModel,
                automaticallyStartsSession: false,
                initiallyShowsFinishConfirmation: showsFinishConfirmation
            )
        }
    }
    #endif
}
