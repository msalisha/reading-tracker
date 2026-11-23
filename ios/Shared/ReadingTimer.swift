import Foundation

/// The one reading timer. Kept in the shared App Group so the app, the lock-screen Live Activity
/// and the widgets all see the same thing, and so it keeps counting when the app is closed.
struct ActiveTimer: Codable, Equatable {
    enum Status: String, Codable { case running, paused, stopped }

    var bookID: String
    var bookTitle: String
    var startPage: Int
    var startedAt: Date
    var accumulated: TimeInterval = 0
    var runningSince: Date?
    var status: Status

    func elapsed(at now: Date = .now) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Whole minutes for the log, never less than 1.
    func minutes(at now: Date = .now) -> Int { max(1, Int((elapsed(at: now) / 60).rounded())) }

    /// The moment the clock would read 0:00 if it had never paused; lets iOS tick the clock itself.
    var clockStart: Date { (runningSince ?? .now).addingTimeInterval(-accumulated) }

    mutating func pause(at now: Date = .now) {
        guard status == .running else { return }
        accumulated = elapsed(at: now)
        runningSince = nil
        status = .paused
    }

    mutating func resume(at now: Date = .now) {
        guard status != .running else { return }
        runningSince = now
        status = .running
    }

    mutating func stop(at now: Date = .now) {
        accumulated = elapsed(at: now)
        runningSince = nil
        status = .stopped
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds), h = s / 3600, m = (s / 60) % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s % 60))"
                     : "\(m):\(String(format: "%02d", s % 60))"
    }
}

enum TimerStorage {
    private static let key = "activeTimer"

    static func load() -> ActiveTimer? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveTimer.self, from: data)
    }

    static func save(_ timer: ActiveTimer?) {
        if let timer, let data = try? JSONEncoder().encode(timer) {
            AppGroup.defaults.set(data, forKey: key)
        } else {
            AppGroup.defaults.removeObject(forKey: key)
        }
    }
}
