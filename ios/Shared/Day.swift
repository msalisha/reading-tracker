import Foundation

extension Date {
    /// Seconds since 2001, as a plain number. Compare these instead of comparing dates with < or >=:
    /// apps built with a newer Xcode can call date operators that older iOS versions don't have,
    /// which crashes on those phones.
    var seconds: TimeInterval { timeIntervalSinceReferenceDate }
}

/// Calendar helpers. Days are kept as "yyyy-MM-dd" keys in the reader's own time zone, the same as the web app.
enum Day {
    /// A plain value (no shared formatter objects), so it's safe to use from anywhere.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent
        c.firstWeekday = 2 // weeks start on Monday
        return c
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func monthKey(_ date: Date) -> String { String(key(date).prefix(7)) }

    /// Midnight at the start of the day a key names (or of the month, for a "yyyy-MM" key).
    static func date(_ key: String) -> Date {
        let parts = key.prefix(10).split(separator: "-").map { Int($0) }
        guard parts.count >= 2, let y = parts[0], let m = parts[1] else { return .distantPast }
        let d = parts.count >= 3 ? (parts[2] ?? 1) : 1
        return calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? .distantPast
    }

    static func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func startOfWeek(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start) // Sunday = 1
        return add(-((weekday + 5) % 7), to: start)
    }

    static func firstOfMonth(_ date: Date, offset: Int = 0) -> Date {
        let c = calendar
        let comps = c.dateComponents([.year, .month], from: date)
        let first = c.date(from: comps) ?? date
        return c.date(byAdding: .month, value: offset, to: first) ?? first
    }

    static func daysInMonth(_ date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func dayOfMonth(_ date: Date) -> Int { calendar.component(.day, from: date) }

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "13 Nov"
    static func short(_ key: String) -> String {
        let d = date(key)
        return "\(dayOfMonth(d)) \(months[calendar.component(.month, from: d) - 1])"
    }

    /// "Fri 13 Nov 2026"
    static func long(_ key: String) -> String {
        date(key).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "Nov 2026"
    static func month(_ key: String) -> String {
        let d = date(key)
        return "\(months[calendar.component(.month, from: d) - 1]) \(calendar.component(.year, from: d))"
    }

    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }
}
