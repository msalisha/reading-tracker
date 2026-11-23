import Foundation

/// A small summary the app writes for the widgets after every change, so widgets never touch the database.
struct WidgetSnapshot: Codable {
    struct CurrentBook: Codable {
        var id: String
        var title: String
        var author: String
        var page: Int
        var totalPages: Int
        var cover: Data?
    }

    /// Pages per day for the last 400 days ("yyyy-MM-dd" → pages).
    var pagesByDay: [String: Int] = [:]
    var currentBook: CurrentBook?
    var booksThisMonth = 0
    var updatedAt = Date()

    func streak(now: Date = .now) -> Int { Stats.streak(pagesByDay, now: now) }
    func pagesToday(now: Date = .now) -> Int { pagesByDay[Day.key(now)] ?? 0 }

    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return snap
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { AppGroup.defaults.set(data, forKey: Self.key) }
    }
}
