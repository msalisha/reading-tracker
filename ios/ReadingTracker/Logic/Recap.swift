import Foundation

/// The numbers behind a monthly recap or a year in review.
struct Recap {
    enum Period: Hashable, Identifiable {
        case month(year: Int, month: Int)
        case year(Int)

        var id: String { firstDay }

        static func thisMonth(_ now: Date) -> Period {
            let c = Day.calendar.dateComponents([.year, .month], from: now)
            return .month(year: c.year ?? 2026, month: c.month ?? 1)
        }
        static func lastMonth(_ now: Date) -> Period { thisMonth(Day.firstOfMonth(now, offset: -1)) }
        static func thisYear(_ now: Date) -> Period { .year(Day.calendar.component(.year, from: now)) }
        static func lastYear(_ now: Date) -> Period { .year(Day.calendar.component(.year, from: now) - 1) }

        var firstDay: String {
            switch self {
            case .month(let y, let m): return String(format: "%04d-%02d-01", y, m)
            case .year(let y): return String(format: "%04d-01-01", y)
            }
        }

        var lastDay: String {
            switch self {
            case .month(let y, let m):
                return String(format: "%04d-%02d-%02d", y, m, Day.daysInMonth(Day.date(firstDay)))
            case .year(let y): return String(format: "%04d-12-31", y)
            }
        }

        /// "November 2026" or "2026".
        var title: String {
            switch self {
            case .month(let y, let m): return "\(Day.date(firstDay).formatted(.dateTime.month(.wide))) \(y)"
            case .year(let y): return "\(y)"
            }
        }

        /// "November" or "2026", for "Your November in books".
        var shortTitle: String {
            switch self {
            case .month: return Day.date(firstDay).formatted(.dateTime.month(.wide))
            case .year(let y): return "\(y)"
            }
        }

        var isYear: Bool { if case .year = self { return true } else { return false } }

        func contains(_ day: String?) -> Bool {
            guard let day else { return false }
            return day >= firstDay && day <= lastDay
        }
    }

    struct Quote: Equatable {
        var text: String
        var bookTitle: String
        var author: String
    }

    var period: Period
    var finished: [BookSnap] = []
    var writtenOff = 0
    var pages = 0
    /// Minutes of audiobook listened to.
    var listened = 0
    var minutes = 0
    var sessions = 0
    var readingDays = 0
    /// Days so far in the period (all of it once it's over).
    var daysElapsed = 0
    var longestStreak = 0
    var bestDay: (day: String, pages: Int)?
    var topBook: BookSnap?
    var averageRating: Double?
    var longestBook: BookSnap?
    var fastest: (book: BookSnap, days: Int)?
    var favouriteWeekday: String?
    var quote: Quote?

    var isEmpty: Bool { pages == 0 && listened == 0 && finished.isEmpty }
    var hours: Double { Double(minutes) / 60 }

    struct NoteInput {
        var text: String
        var isQuote: Bool
        var day: String
        var bookTitle: String
        var author: String
    }

    static func make(_ period: Period, books: [BookSnap], sessions: [SessionSnap], notes: [NoteInput], now: Date) -> Recap {
        var r = Recap(period: period)
        let today = Day.key(now)
        let end = min(period.lastDay, today)

        // Reading
        let mine = sessions.filter { period.contains($0.day) }
        r.sessions = mine.count
        r.pages = mine.filter { !$0.isAudio }.reduce(0) { $0 + max(0, $1.pages) }
        r.listened = mine.filter(\.isAudio).reduce(0) { $0 + max(0, $1.pages) }
        r.minutes = mine.compactMap(\.minutes).reduce(0, +)
        let pbd = Stats.activityByDay(mine)          // any reading or listening makes it a reading day
        let readDays = pbd.filter { $0.value > 0 }
        r.readingDays = readDays.count
        if let best = Stats.pagesByDay(mine).filter({ $0.value > 0 }).max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            r.bestDay = (best.key, best.value)
        }

        // Days so far, and the longest run of reading days inside the period.
        var day = Day.date(period.firstDay), run = 0
        while Day.key(day) <= end {
            r.daysElapsed += 1
            if (pbd[Day.key(day)] ?? 0) > 0 { run += 1; r.longestStreak = max(r.longestStreak, run) } else { run = 0 }
            day = Day.add(1, to: day)
        }

        // Which weekday you read the most on (by pages).
        var byWeekday: [Int: Int] = [:]
        for (k, v) in readDays { byWeekday[Day.calendar.component(.weekday, from: Day.date(k)), default: 0] += v }
        if let top = byWeekday.max(by: { $0.value < $1.value }) {
            r.favouriteWeekday = Day.calendar.weekdaySymbols[top.key - 1]
        }

        // Books
        r.finished = books.filter { $0.status == .finished && period.contains($0.finishedDay) }
            .sorted { ($0.finishedDay ?? "") < ($1.finishedDay ?? "") }
        r.writtenOff = books.filter { $0.status == .dnf && period.contains($0.dnfDay) }.count
        r.averageRating = Stats.averageRating(r.finished)
        r.topBook = r.finished.filter { ($0.rating ?? 0) > 0 }
            .max { ($0.rating ?? 0, $0.finishedDay ?? "") < ($1.rating ?? 0, $1.finishedDay ?? "") }
        r.longestBook = r.finished.filter { !$0.isAudio }.max { $0.totalPages < $1.totalPages }
        let timed = r.finished.compactMap { b in Stats.daysTaken(b, sessions: sessions).map { (book: b, days: $0) } }
        r.fastest = timed.min { $0.days < $1.days }

        // A quote from the period: the most recent one, if any.
        if let q = notes.filter({ $0.isQuote && period.contains($0.day) }).max(by: { $0.day < $1.day }) {
            r.quote = Quote(text: q.text, bookTitle: q.bookTitle, author: q.author)
        }
        return r
    }
}
