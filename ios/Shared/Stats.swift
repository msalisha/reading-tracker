import Foundation

enum BookStatus: String, Codable, CaseIterable {
    case wantToRead, reading, finished, dnf
}

/// Plain copies of the stored data, so the maths can be tested (and used by widgets) without the database.
struct BookSnap: Identifiable, Hashable {
    var id: String
    var title: String
    var author: String = ""
    var totalPages: Int
    var startPage: Int = 0
    var status: BookStatus = .reading
    var finishedDay: String? = nil
    var dnfDay: String? = nil
    var rating: Double? = nil
    var addedAt: Date = .now
    var lastAt: Date = .now
    /// An audiobook: its length and positions are minutes, not pages.
    var isAudio: Bool = false

    /// "432 pages" or "11h 05m".
    var lengthText: String { isAudio ? Stats.formatMinutes(Double(totalPages)) : "\(totalPages.formatted()) pages" }
}

struct SessionSnap: Identifiable, Hashable {
    var id: String
    var bookID: String
    var day: String
    var startedAt: Date
    var startPage: Int
    var endPage: Int
    var pages: Int
    var minutes: Int? = nil
    /// A listening session: `pages` and the positions are minutes of the recording.
    var isAudio: Bool = false

    /// "p. 100 → 138" or "1h 05m → 1h 40m".
    var rangeText: String {
        isAudio ? "\(Stats.formatMinutes(Double(startPage))) → \(Stats.formatMinutes(Double(endPage)))" : "p. \(startPage) → \(endPage)"
    }
    /// "+38" pages or "+35 min".
    var gainText: String { isAudio ? "+" + Stats.formatMinutes(Double(pages)) : "+\(pages)" }
}

struct Scores: Equatable {
    var today = 0
    var week = 0
    var lastWeekSoFar = 0
    var month = 0
    var lastMonthSoFar = 0
    var finishedThisMonth = 0
    var dnfThisMonth = 0
    var streak = 0
    /// Minutes of audiobook listened to.
    var listenedToday = 0
    var listenedWeek = 0
    var listenedMonth = 0
}

struct Pace: Equatable {
    var current: Int
    var left: Int
    var etaDays: Int?
    var hasSessions: Bool
    var fraction: Double
    var isAudio = false
    var total = 0

    var line: String {
        guard hasSessions else { return "No sessions yet" }
        let leftText = isAudio ? Stats.formatMinutes(Double(left)) : left.formatted()
        if let eta = etaDays { return "\(leftText) left · about \(eta) \(eta == 1 ? "day" : "days") at your pace" }
        return isAudio ? "\(leftText) left" : "\(leftText) pages left"
    }

    /// "Page 138 of 432" or "3h 20m of 11h 05m".
    var position: String {
        isAudio ? "\(Stats.formatMinutes(Double(current))) of \(Stats.formatMinutes(Double(total)))"
                : "Page \(current.formatted()) of \(total.formatted())"
    }
}

/// One bar in a chart. `secondary` stacks on top (books written off).
struct Bar: Identifiable, Hashable {
    var id: String
    var label: String
    var value: Int
    var secondary: Int = 0
    var isCurrent = false
    var detail = ""
}

struct DayTotals: Identifiable, Hashable {
    var id: String { day }
    var day: String
    var minutes: Int
    var pages: Int
}

struct AverageDay {
    var avgMinutes: Double
    var avgPages: Double
    var timedDays: Int
    var readDays: Int
    var pagesPerHour: Double?
    var series: [DayTotals]
}

struct MonthSummary {
    var finished: [BookSnap]
    var writtenOff: [BookSnap]
    var lastMonthFinished: Int
    var pages: Int
    var readDays: Set<String>
    var finishDays: Set<String>
    var daysLeft: Int
}

enum ChartRange: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// All the reading maths, ported one-for-one from the web app.
enum Stats {
    static func currentPage(_ book: BookSnap, sessions: [SessionSnap]) -> Int {
        var page = book.startPage
        for s in sessions where s.bookID == book.id && s.endPage > page { page = s.endPage }
        return min(page, book.totalPages)
    }

    /// Pages read per day (print books only).
    static func pagesByDay(_ sessions: [SessionSnap]) -> [String: Int] {
        var m: [String: Int] = [:]
        for s in sessions where !s.isAudio { m[s.day, default: 0] += max(0, s.pages) }
        return m
    }

    /// Minutes of audiobook listened to per day.
    static func listenedByDay(_ sessions: [SessionSnap]) -> [String: Int] {
        var m: [String: Int] = [:]
        for s in sessions where s.isAudio { m[s.day, default: 0] += max(0, s.pages) }
        return m
    }

    /// Days with any reading or listening, for streaks and calendars.
    static func activityByDay(_ sessions: [SessionSnap]) -> [String: Int] {
        var m: [String: Int] = [:]
        for s in sessions { m[s.day, default: 0] += max(0, s.pages) }
        return m
    }

    /// Days in a row with pages, counting back from today (or from yesterday if nothing is logged yet today).
    static func streak(_ pagesByDay: [String: Int], now: Date) -> Int {
        var d = now
        if (pagesByDay[Day.key(d)] ?? 0) <= 0 { d = Day.add(-1, to: d) }
        var n = 0
        while (pagesByDay[Day.key(d)] ?? 0) > 0 {
            n += 1
            d = Day.add(-1, to: d)
        }
        return n
    }

    static func scores(books: [BookSnap], sessions: [SessionSnap], now: Date) -> Scores {
        let pbd = pagesByDay(sessions)
        let today = Day.key(now)
        let weekStart = Day.startOfWeek(now)
        let lastWeekStart = Day.add(-7, to: weekStart)
        let daysIntoWeek = Day.daysBetween(weekStart, now)
        let mk = Day.monthKey(now)
        let lastMk = Day.monthKey(Day.firstOfMonth(now, offset: -1))
        let dom = Day.dayOfMonth(now)

        var s = Scores()
        s.today = pbd[today] ?? 0
        for (k, v) in pbd {
            let d = Day.date(k)
            if d.seconds >= weekStart.seconds && k <= today {
                s.week += v
            } else if d.seconds >= lastWeekStart.seconds && d.seconds < weekStart.seconds && Day.daysBetween(lastWeekStart, d) <= daysIntoWeek {
                s.lastWeekSoFar += v
            }
            if k.hasPrefix(mk) {
                s.month += v
            } else if k.hasPrefix(lastMk) && Day.dayOfMonth(d) <= dom {
                s.lastMonthSoFar += v
            }
        }
        for (k, v) in listenedByDay(sessions) {
            if k == today { s.listenedToday += v }
            if Day.date(k).seconds >= weekStart.seconds && k <= today { s.listenedWeek += v }
            if k.hasPrefix(mk) { s.listenedMonth += v }
        }
        s.finishedThisMonth = books.filter { $0.status == .finished && ($0.finishedDay ?? "").hasPrefix(mk) }.count
        s.dnfThisMonth = books.filter { $0.status == .dnf && ($0.dnfDay ?? "").hasPrefix(mk) }.count
        s.streak = streak(activityByDay(sessions), now: now)
        return s
    }

    /// "+80 vs last week", "nothing last week by now", or "so far".
    static func versus(_ current: Int, _ previous: Int, _ label: String) -> String {
        if previous == 0 { return current > 0 ? "nothing \(label) by now" : "so far" }
        let diff = current - previous
        return "\(diff >= 0 ? "+" : "−")\(abs(diff).formatted()) vs \(label)"
    }

    /// Progress plus an estimate from the last 14 days of reading this book.
    static func pace(_ book: BookSnap, sessions: [SessionSnap], now: Date) -> Pace {
        let current = currentPage(book, sessions: sessions)
        let left = max(0, book.totalPages - current)
        let mine = sessions.filter { $0.bookID == book.id }
        let cut = Day.key(Day.add(-13, to: now))
        let recent = mine.filter { $0.day >= cut }.reduce(0) { $0 + $1.pages }
        let perDay = Double(recent) / 14
        let eta = perDay > 0 ? Int((Double(left) / perDay).rounded(.up)) : nil
        let fraction = book.totalPages > 0 ? min(1, Double(current) / Double(book.totalPages)) : 0
        return Pace(current: current, left: left, etaDays: eta, hasSessions: !mine.isEmpty, fraction: fraction,
                    isAudio: book.isAudio, total: book.totalPages)
    }

    /// Page reached over time for a book, for its little progress line.
    static func progressLine(_ book: BookSnap, sessions: [SessionSnap]) -> [(Date, Int)] {
        let mine = sessions.filter { $0.bookID == book.id }.sorted { $0.startedAt.seconds < $1.startedAt.seconds }
        guard let first = mine.first else { return [] }
        var points: [(Date, Int)] = [(first.startedAt.addingTimeInterval(-43_200), min(book.startPage, first.startPage))]
        var reached = 0
        for s in mine {
            reached = max(reached, s.endPage)
            points.append((s.startedAt, reached))
        }
        return points
    }

    /// Bars of pages read, or of minutes listened when `audio` is true.
    static func pageBars(_ range: ChartRange, sessions: [SessionSnap], now: Date, audio: Bool = false) -> [Bar] {
        let pbd = audio ? listenedByDay(sessions) : pagesByDay(sessions)
        func amount(_ v: Int) -> String { audio ? formatMinutes(Double(v)) : "\(v.formatted()) pages" }
        var bars: [Bar] = []
        switch range {
        case .day:
            for i in stride(from: 13, through: 0, by: -1) {
                let k = Day.key(Day.add(-i, to: now))
                let v = pbd[k] ?? 0
                bars.append(Bar(id: k, label: i == 0 ? "Today" : Day.short(k), value: v, isCurrent: i == 0,
                                detail: "\(Day.long(k)): \(amount(v))"))
            }
        case .week:
            let ws = Day.startOfWeek(now)
            for i in stride(from: 7, through: 0, by: -1) {
                let start = Day.add(-7 * i, to: ws)
                var v = 0
                for j in 0..<7 { v += pbd[Day.key(Day.add(j, to: start))] ?? 0 }
                let k = Day.key(start)
                bars.append(Bar(id: k, label: i == 0 ? "This wk" : Day.short(k), value: v, isCurrent: i == 0,
                                detail: "Week of \(Day.short(k)): \(amount(v))"))
            }
        case .month:
            for i in stride(from: 11, through: 0, by: -1) {
                let mk = Day.monthKey(Day.firstOfMonth(now, offset: -i))
                let v = pbd.filter { $0.key.hasPrefix(mk) }.reduce(0) { $0 + $1.value }
                bars.append(Bar(id: mk, label: String(Day.month(mk).prefix(3)), value: v, isCurrent: i == 0,
                                detail: "\(Day.month(mk)): \(amount(v))"))
            }
        }
        return bars
    }

    static func pageBarsSummary(_ range: ChartRange, bars: [Bar], audio: Bool = false) -> String {
        let total = bars.reduce(0) { $0 + $1.value }
        if audio {
            let t = formatMinutes(Double(total))
            switch range {
            case .day: return "\(t) listened in the last 14 days · \(formatMinutes(Double(total) / 14)) a day"
            case .week: return "\(t) listened in the last 8 weeks · \(formatMinutes(Double(total) / 8)) a week"
            case .month: return "\(t) listened in the last 12 months"
            }
        }
        switch range {
        case .day: return "\(total.formatted()) pages in the last 14 days · \(Int((Double(total) / 14).rounded())) a day"
        case .week: return "\(total.formatted()) pages in the last 8 weeks · \(Int((Double(total) / 8).rounded())) a week"
        case .month: return "\(total.formatted()) pages in the last 12 months"
        }
    }

    /// Minutes and pages per day over the last `days`, averaged over the days you actually read.
    static func averageDay(sessions: [SessionSnap], days: Int, now: Date) -> AverageDay {
        let cut = Day.key(Day.add(-(days - 1), to: now))
        var pages: [String: Int] = [:], mins: [String: Int] = [:]
        var pacePages = 0, paceMins = 0
        for s in sessions where s.day >= cut {
            if !s.isAudio { pages[s.day, default: 0] += max(0, s.pages) }
            if let m = s.minutes, m > 0 {
                mins[s.day, default: 0] += m
                if !s.isAudio {   // reading speed is about pages, so listening doesn't count towards it
                    pacePages += s.pages
                    paceMins += m
                }
            }
        }
        let pageDays = pages.filter { $0.value > 0 }
        let avgP = pageDays.isEmpty ? 0 : Double(pageDays.values.reduce(0, +)) / Double(pageDays.count)
        let avgM = mins.isEmpty ? 0 : Double(mins.values.reduce(0, +)) / Double(mins.count)
        var series: [DayTotals] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let k = Day.key(Day.add(-i, to: now))
            series.append(DayTotals(day: k, minutes: mins[k] ?? 0, pages: pages[k] ?? 0))
        }
        return AverageDay(avgMinutes: avgM, avgPages: avgP, timedDays: mins.count, readDays: pageDays.count,
                          pagesPerHour: paceMins > 0 ? Double(pacePages) / Double(paceMins) * 60 : nil, series: series)
    }

    static func bookBars(books: [BookSnap], now: Date) -> [Bar] {
        (0...11).reversed().map { i in
            let mk = Day.monthKey(Day.firstOfMonth(now, offset: -i))
            let fin = books.filter { $0.status == .finished && ($0.finishedDay ?? "").hasPrefix(mk) }
            let dnf = books.filter { $0.status == .dnf && ($0.dnfDay ?? "").hasPrefix(mk) }
            return Bar(id: mk, label: String(Day.month(mk).prefix(3)), value: fin.count, secondary: dnf.count, isCurrent: i == 0,
                       detail: "\(Day.month(mk)): \(fin.count) finished" + (dnf.isEmpty ? "" : ", \(dnf.count) written off"))
        }
    }

    static func month(books: [BookSnap], sessions: [SessionSnap], now: Date) -> MonthSummary {
        let mk = Day.monthKey(now)
        let lastMk = Day.monthKey(Day.firstOfMonth(now, offset: -1))
        let fin = books.filter { $0.status == .finished && ($0.finishedDay ?? "").hasPrefix(mk) }
            .sorted { ($0.finishedDay ?? "") < ($1.finishedDay ?? "") }
        let dnf = books.filter { $0.status == .dnf && ($0.dnfDay ?? "").hasPrefix(mk) }
        let lastN = books.filter { $0.status == .finished && ($0.finishedDay ?? "").hasPrefix(lastMk) }.count
        let pbd = pagesByDay(sessions).filter { $0.key.hasPrefix(mk) }
        return MonthSummary(finished: fin, writtenOff: dnf, lastMonthFinished: lastN,
                            pages: pbd.values.reduce(0, +),
                            readDays: Set(activityByDay(sessions).filter { $0.key.hasPrefix(mk) && $0.value > 0 }.keys),
                            finishDays: Set(fin.compactMap(\.finishedDay)),
                            daysLeft: Day.daysInMonth(now) - Day.dayOfMonth(now))
    }

    /// How many days a finished book took, from its first session to the day it was finished.
    static func daysTaken(_ book: BookSnap, sessions: [SessionSnap]) -> Int? {
        guard let fin = book.finishedDay,
              let first = sessions.filter({ $0.bookID == book.id }).map(\.day).min() else { return nil }
        return max(1, Day.daysBetween(Day.date(first), Day.date(fin)) + 1)
    }

    static func averageRating(_ books: [BookSnap]) -> Double? {
        let r = books.compactMap(\.rating).filter { $0 > 0 }
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }

    static func formatMinutes(_ m: Double) -> String {
        m >= 60 ? "\(Int(m) / 60)h \(String(format: "%02d", Int(m.rounded()) % 60))m" : "\(Int(m.rounded())) min"
    }
}
