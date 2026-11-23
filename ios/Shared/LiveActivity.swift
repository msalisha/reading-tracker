import Foundation
import ActivityKit
import AppIntents
import WidgetKit

/// What the lock screen and Dynamic Island show while the timer is going.
struct ReadingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var clockStart: Date
        var elapsed: TimeInterval
        var startPage: Int
    }
    var bookID: String
    var bookTitle: String
}

extension ReadingActivityAttributes.ContentState {
    init(_ t: ActiveTimer) {
        self.init(isRunning: t.status == .running, clockStart: t.clockStart, elapsed: t.elapsed(), startPage: t.startPage)
    }
}

/// Starts, updates and ends the Live Activity. Only the app itself does this; the widget extension compiles it as no-ops.
enum LiveActivityController {
    static func start(_ timer: ActiveTimer) {
        #if !WIDGET_EXTENSION
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            await endAll()
            _ = try? Activity.request(
                attributes: ReadingActivityAttributes(bookID: timer.bookID, bookTitle: timer.bookTitle),
                content: .init(state: .init(timer), staleDate: nil))
        }
        #endif
    }

    static func update(_ timer: ActiveTimer) async {
        #if !WIDGET_EXTENSION
        for activity in Activity<ReadingActivityAttributes>.activities {
            await activity.update(.init(state: .init(timer), staleDate: nil))
        }
        #endif
    }

    static func endAll() async {
        #if !WIDGET_EXTENSION
        for activity in Activity<ReadingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}

/// Lock-screen Pause button. LiveActivityIntent runs in the app's process.
struct PauseReadingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause reading timer"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        if var t = TimerStorage.load(), t.status == .running {
            t.pause()
            TimerStorage.save(t)
            await LiveActivityController.update(t)
        }
        await MainActor.run { NotificationCenter.default.post(name: .readingTimerChanged, object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Lock-screen Resume button.
struct ResumeReadingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume reading timer"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        if var t = TimerStorage.load(), t.status != .running {
            t.resume()
            TimerStorage.save(t)
            await LiveActivityController.update(t)
        }
        await MainActor.run { NotificationCenter.default.post(name: .readingTimerChanged, object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
