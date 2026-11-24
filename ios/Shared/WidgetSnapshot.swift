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
        var isAudio: Bool? = nil

        /// "Page 148 of 432" or "3h 20m of 11h 05m".
        var positionText: String {
            isAudio == true ? "\(Stats.formatMinutes(Double(page))) of \(Stats.formatMinutes(Double(totalPages)))"
                            : "Page \(page) of \(totalPages)"
        }
    }

    /// Pages per day for the last 400 days ("yyyy-MM-dd" → pages).
    var pagesByDay: [String: Int] = [:]
    /// Minutes of audiobook listened to per day.
    var listenedByDay: [String: Int]? = nil
    var currentBook: CurrentBook?
    var booksThisMonth = 0
    var updatedAt = Date()

    /// A day counts towards the streak with any reading or listening.
    func streak(now: Date = .now) -> Int {
        Stats.streak(pagesByDay.merging(listenedByDay ?? [:], uniquingKeysWith: +), now: now)
    }
    func pagesToday(now: Date = .now) -> Int { pagesByDay[Day.key(now)] ?? 0 }
    /// "24 pages today", "40 min listened today", or both.
    func todayText(now: Date = .now) -> String {
        let pages = pagesToday(now: now), listened = listenedByDay?[Day.key(now)] ?? 0
        if listened > 0 && pages == 0 { return "\(Stats.formatMinutes(Double(listened))) listened today" }
        return "\(pages) pages" + (listened > 0 ? " · \(Stats.formatMinutes(Double(listened)))" : "") + " today"
    }

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
