import SwiftUI
import SwiftData

@main
struct ReadingTrackerApp: App {
    @State private var store: Store
    @State private var timer = TimerModel()
    @State private var router = Router()
    @State private var container: ModelContainer
    private let uiTest: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uitest")
        self.uiTest = uiTest
        let container = Persistence.makeContainer(inMemory: uiTest)
        _container = State(initialValue: container)
        if !uiTest { Sync.watch(container) }
        var forced: Access?
        #if DEBUG
        // UI tests and screenshots: -access unlocked|trial|expired|none
        if let i = args.firstIndex(of: "-access"), i + 1 < args.count {
            switch args[i + 1] {
            case "unlocked": forced = .unlocked
            case "trial": forced = .trial(endsAt: Date().addingTimeInterval(2 * 86_400 + 3600))
            case "expired": forced = .expired
            case "none": forced = .noTrial
            default: break
            }
        }
        #endif
        _store = State(initialValue: Store(forced: forced))
        if uiTest {
            TimerStorage.save(nil)
            AppGroup.defaults.removeObject(forKey: AppTheme.storageKey)
            AppGroup.defaults.removeObject(forKey: "iCloudSyncEnabled")
            if args.contains("-uitest-sample") {
                SampleData.insert(into: container.mainContext)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(timer)
                .environment(router)
                .modelContainer(container)
                .id(ObjectIdentifier(container))   // a fresh view tree (and queries) for a reopened library
                .onChange(of: router.libraryGeneration) { _, _ in
                    guard !uiTest else { return }
                    container = Persistence.makeContainer()
                    Sync.watch(container)
                }
        }
    }
}
