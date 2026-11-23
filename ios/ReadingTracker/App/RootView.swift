import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(TimerModel.self) private var timer
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @AppStorage(AppTheme.storageKey, store: AppGroup.defaults) private var themeID = "neon"
    @AppStorage("appearance") private var appearance = "system"
    /// Chose "Look around first" on the welcome screen this launch.
    @State private var lookingAround = false

    private var theme: AppTheme { AppTheme.named(themeID) }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "timer") }
                .tag(Router.Tab.today)
            BooksView()
                .tabItem { Label("Books", systemImage: "books.vertical") }
                .tag(Router.Tab.books)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(Router.Tab.stats)
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet") }
                .tag(Router.Tab.log)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
        .modernTabBar()
        .tint(theme.brandText)
        .environment(\.theme, theme)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(isPresented: $router.showPaywall) {
            PaywallView().environment(\.theme, theme)
        }
        .sheet(item: Binding(get: { router.rateBookID.map(RateTarget.init) }, set: { router.rateBookID = $0?.id })) { target in
            if let book = Library.book(ctx, uid: target.id) {
                RateBookSheet(book: book).environment(\.theme, theme)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { store.access == .noTrial && !lookingAround }, set: { _ in })) {
            WelcomeView(onLookAround: { lookingAround = true }).environment(\.theme, theme)
        }
        .onOpenURL(perform: open)
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            store.now = Date()
            timer.reload()
            Library.refreshWidgets(ctx)
        }
        .task { Library.refreshWidgets(ctx) }
    }

    /// pageturner://timer opens Today; pageturner://start?book=ID starts the timer for that book.
    private func open(_ url: URL) {
        guard url.scheme == Links.scheme else { return }
        router.tab = .today
        if url.host == "start",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "book" })?.value {
            router.startTimerBookID = id
        }
    }
}

private struct RateTarget: Identifiable {
    let id: String
}
