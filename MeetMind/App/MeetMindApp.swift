import SwiftUI
import SwiftData
import OSLog
import Darwin
import UIKit

final class MeetMindAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OfflineAnalysisBackgroundScheduler.register()
        return true
    }
}

@main
struct MeetMindApp: App {
    @UIApplicationDelegateAdaptor(MeetMindAppDelegate.self) private var appDelegate
    @State private var container: ModelContainer?
    @State private var startupError: String?
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
        
        let state = AppState()
        let navRouter = NavigationRouter()
        let settings = SettingsViewModel()
        
        _appState = State(initialValue: state)
        _router = State(initialValue: navRouter)
        _settingsVM = State(initialValue: settings)
        if ProcessInfo.processInfo.arguments.contains("--diagnose-storage") {
            // Content-free verification of the actual production store open.
            print("MEETMIND_STORAGE_READY \(initializedContainer != nil)")
            fflush(stdout)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    Group {
                        if ProcessInfo.processInfo.arguments.contains("--offline-benchmark") {
                            NavigationStack { OfflineBenchmarkView() }
                        } else if ProcessInfo.processInfo.arguments.contains("--offline-pipeline-smoke") {
                            OfflinePipelineSmokeView()
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
                .environment(appState)
                .environment(router)
                .environment(settingsVM)
                .onOpenURL { url in
                    _ = router.handleDeepLink(url: url, appState: appState)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                settingsVM.recalculateStorageUsage()
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

    @ViewBuilder
    private var appContent: some View {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-microphone-sample") {
            MicrophoneCheckView(onStartRecording: {}, visualSampleDuration: 6)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-microphone") {
            MicrophoneCheckView(onStartRecording: {})
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
