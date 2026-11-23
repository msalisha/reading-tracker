import Foundation

/// The App Group shared by the app and its widgets. Its id comes from the APP_GROUP build setting (see project.yml).
enum AppGroup {
    static let id: String = (Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String) ?? "group.com.example.readingtracker"

    /// Shared settings. Falls back to the app's own defaults when the group isn't available (e.g. unsigned CI builds).
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

enum Links {
    static let privacy = URL(string: "https://msalisha.github.io/reading-tracker/privacy.html")!
    static let support = URL(string: "https://msalisha.github.io/reading-tracker/support.html")!
    static let scheme = "readingtracker"
}

extension Notification.Name {
    /// Posted when the timer changes outside the app's own UI (lock-screen buttons).
    static let readingTimerChanged = Notification.Name("readingTimerChanged")
}
