import Foundation
import Observation
import WidgetKit

/// The app's view of the shared reading timer.
@MainActor
@Observable
final class TimerModel {
    private(set) var timer: ActiveTimer?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        timer = TimerStorage.load()
        FocusSoundPlayer.shared.timerChanged(running: timer?.status == .running)
        observer = NotificationCenter.default.addObserver(forName: .readingTimerChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        timer = TimerStorage.load()
        FocusSoundPlayer.shared.timerChanged(running: timer?.status == .running)
    }

    func start(book: Book, startPage: Int) {
        guard timer == nil else { return }
        let t = ActiveTimer(bookID: book.uid, bookTitle: book.title, startPage: startPage, startedAt: .now,
                            accumulated: 0, runningSince: .now, status: .running)
        write(t)
        LiveActivityController.start(t)
        Haptics.tap()
    }

    func pause() { change { $0.pause() } }
    func resume() { change { $0.resume() } }
    func stop() { change { $0.stop() }; Haptics.tap() }

    func setStartPage(_ page: Int) {
        guard var t = timer, t.startPage != page else { return }
        t.startPage = page
        write(t)
    }

    /// Clears the timer, after logging or when discarded.
    func clear() {
        write(nil)
        Task { await LiveActivityController.endAll() }
    }

    private func change(_ edit: (inout ActiveTimer) -> Void) {
        guard var t = timer else { return }
        edit(&t)
        write(t)
        Task { await LiveActivityController.update(t) }
    }

    private func write(_ t: ActiveTimer?) {
        timer = t
        TimerStorage.save(t)
        FocusSoundPlayer.shared.timerChanged(running: t?.status == .running)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Which tab is showing, plus the app-wide sheets.
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case today, books, stats, log, settings }
    var tab: Tab = .today
    var showPaywall = false
    /// Set after a book is finished, to offer a rating.
    var rateBookID: String?
    /// Asks the Today tab to open the log sheet for a book.
    var logBookID: String?
    /// Asks the Today tab to start a timer for a book (from a widget).
    var startTimerBookID: String?
    /// Bumped when the iCloud sync switch changes, so the app reopens the library with the new setting.
    var libraryGeneration = 0
}
