import SwiftUI
import SwiftData

@main
struct ReadingTrackerApp: App {
    @State private var store: Store
    @State private var timer = TimerModel()
    @State private var router = Router()
    private let container: ModelContainer

    init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uitest")
        container = Persistence.makeContainer(inMemory: uiTest)
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
        }
        .modelContainer(container)
    }
}
