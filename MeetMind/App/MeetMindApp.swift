import SwiftUI
import SwiftData
import OSLog
import Darwin

@main
struct MeetMindApp: App {
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
                if ProcessInfo.processInfo.arguments.contains("--offline-benchmark") {
                    NavigationStack { OfflineBenchmarkView() }
                } else if let container {
                    RootView()
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
                break
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
