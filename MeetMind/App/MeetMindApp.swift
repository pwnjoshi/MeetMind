import SwiftUI
import SwiftData

@main
struct MeetMindApp: App {
    private let container: ModelContainer
    @State private var appState: AppState
    @State private var router: NavigationRouter
    @State private var settingsVM: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let initializedContainer: ModelContainer
        do {
            initializedContainer = try ModelContainerFactory.createProductionContainer()
        } catch {
            print("Production ModelContainer creation failed: \(error). Falling back to in-memory container.")
            do {
                initializedContainer = try ModelContainerFactory.createInMemoryContainer()
            } catch {
                fatalError("Critical ModelContainer initialization failure: \(error)")
            }
        }
        self.container = initializedContainer
        
        Task { @MainActor in
            let context = initializedContainer.mainContext
            var descriptor = FetchDescriptor<Meeting>()
            descriptor.fetchLimit = 1
            if (try? context.fetchCount(descriptor)) == 0 {
                SampleDataGenerator.populateSampleData(context: context)
                try? context.save()
            }
        }
        
        let state = AppState()
        let navRouter = NavigationRouter()
        let settings = SettingsViewModel()
        
        _appState = State(initialValue: state)
        _router = State(initialValue: navRouter)
        _settingsVM = State(initialValue: settings)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(router)
                .environment(settingsVM)
                .onOpenURL { url in
                    _ = router.handleDeepLink(url: url, appState: appState)
                }
        }
        .modelContainer(container)
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
