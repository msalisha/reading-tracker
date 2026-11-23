import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(\.theme) private var theme
    @Query private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @AppStorage("statsRange") private var rangeRaw = ChartRange.day.rawValue
    @AppStorage("statsDays") private var avgDays = 30
    @State private var recapPeriod: Recap.Period?

    var body: some View {
        let bs = books.map(\.snap), ss = sessions.map(\.snap), now = Date()
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    recapButtons(now)
                    MonthBoard(summary: Stats.month(books: bs, sessions: ss, now: now),
                               reading: books.filter { $0.status == .reading }.map { ($0.snap, Stats.pace($0.snap, sessions: ss, now: now).fraction) },
                               now: now)
                    pagesBoard(ss, now)
                    averageBoard(ss, now)
                    booksBoard(bs, now)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Stats")
            .fullScreenCover(item: $recapPeriod) { p in
                RecapView(period: p).environment(\.theme, theme)
            }
        }
    }

    /// Story-style recaps: this month, and the year so far (last year too during January).
    private func recapButtons(_ now: Date) -> some View {
        let month = Recap.Period.thisMonth(now)
        let year = Day.calendar.component(.month, from: now) == 1 ? Recap.Period.lastYear(now) : Recap.Period.thisYear(now)
        return HStack(spacing: 10) {
            recapButton("Your \(month.shortTitle)", "Monthly recap", icon: "sparkles", fill: theme.brand, text: theme.onBrand) { recapPeriod = month }
                .accessibilityIdentifier("recapMonth")
            recapButton("Your \(year.shortTitle)", "Year in review", icon: "trophy", fill: theme.highlight, text: theme.onHighlight) { recapPeriod = year }
                .accessibilityIdentifier("recapYear")
        }
    }

    private func recapButton(_ title: String, _ sub: String, icon: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.system(.headline, design: .rounded, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Text(sub).font(.caption.weight(.semibold)).opacity(0.8)
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .day }

    private func board<Content: View>(_ title: String, _ sub: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded, weight: .heavy))
                Text(sub).font(.subheadline).foregroundStyle(theme.boardMuted)
            }
            content()
        }
        .foregroundStyle(theme.boardText)
        .card(theme.board, radius: 24, padding: 18)
    }

    private func pagesBoard(_ ss: [SessionSnap], _ now: Date) -> some View {
        let bars = Stats.pageBars(range, sessions: ss, now: now)
        return board("Pages read", Stats.pageBarsSummary(range, bars: bars)) {
            Picker("Group by", selection: $rangeRaw) {
                ForEach(ChartRange.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Chart(bars) { b in
                BarMark(x: .value("When", b.label), y: .value("Pages", b.value))
                    .foregroundStyle(b.isCurrent ? theme.highlight : theme.brand)
                    .cornerRadius(4)
                    .accessibilityLabel(b.detail)
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(theme.boardMuted) } }
            .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(theme.boardGrid)
                AxisValueLabel().foregroundStyle(theme.boardMuted)
            } }
            .frame(height: 200)
        }
    }

    private func averageBoard(_ ss: [SessionSnap], _ now: Date) -> some View {
        let avg = Stats.averageDay(sessions: ss, days: avgDays, now: now)
        let sub = avg.pagesPerHour.map { "About \(Int($0.rounded())) pages an hour, from your timed sessions" }
            ?? "Last \(avgDays) days. Use the timer to see your pace"
        return board("Your average day", sub) {
            Picker("Average over", selection: $avgDays) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            HStack(alignment: .top) {
                stat("Time a day", avg.avgMinutes >= 60 ? Stats.formatMinutes(avg.avgMinutes) : "\(Int(avg.avgMinutes.rounded()))",
                     avg.timedDays > 0 ? (avg.avgMinutes >= 60 ? "" : "minutes · ") + "\(avg.timedDays) timed days" : "time a session to see this",
                     theme.highlight)
                stat("Pages a day", "\(Int(avg.avgPages.rounded()))",
                     avg.readDays > 0 ? "read on \(avg.readDays) of \(avgDays) days" : "nothing logged yet", theme.brand)
            }
            dayChart(avg.series, value: \.minutes, color: theme.highlight, average: avg.avgMinutes, unit: "min")
            dayChart(avg.series, value: \.pages, color: theme.brand, average: avg.avgPages, unit: "pages")
        }
    }

    private func stat(_ label: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label, color: theme.boardMuted)
            BigNumber(text: value, color: color, size: 30)
            Text(sub).font(.caption).foregroundStyle(theme.boardMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayChart(_ series: [DayTotals], value: KeyPath<DayTotals, Int>, color: Color, average: Double, unit: String) -> some View {
        Chart {
            ForEach(series) { d in
                BarMark(x: .value("Day", Day.date(d.day), unit: .day), y: .value(unit, d[keyPath: value]))
                    .foregroundStyle(color)
                    .cornerRadius(2)
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(theme.boardText)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(Int(average.rounded())) \(unit)").font(.caption2.weight(.bold)).foregroundStyle(theme.boardText)
                    }
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(theme.boardMuted) } }
        .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(theme.boardGrid)
                AxisValueLabel().foregroundStyle(theme.boardMuted)
            } }
        .frame(height: 150)
    }

    private func booksBoard(_ bs: [BookSnap], _ now: Date) -> some View {
        let bars = Stats.bookBars(books: bs, now: now)
        let total = bars.reduce(0) { $0 + $1.value }
        let avg = Stats.averageRating(bs.filter { $0.status == .finished })
        let sub = "\(total) \(total == 1 ? "book" : "books") in the last 12 months" + (avg.map { " · average rating \(String(format: "%.1f", $0))★" } ?? "")
        return board("Books finished", sub) {
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("Month", b.label), y: .value("Books", b.value))
                        .foregroundStyle(by: .value("Kind", "Finished"))
                    BarMark(x: .value("Month", b.label), y: .value("Books", b.secondary))
                        .foregroundStyle(by: .value("Kind", "Written off"))
                }
            }
            .chartForegroundStyleScale(["Finished": theme.highlight, "Written off": Color.gray])
            .chartLegend(.visible)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(theme.boardMuted) } }
            .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(theme.boardGrid)
                AxisValueLabel().foregroundStyle(theme.boardMuted)
            } }
            .frame(height: 180)
        }
    }
}

/// This month's finished books as spines on a shelf, beside a calendar of reading days.
struct MonthBoard: View {
    let summary: MonthSummary
    let reading: [(BookSnap, Double)]
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finished in \(Day.monthName(now))").font(.system(.headline, design: .rounded, weight: .heavy))
                    Text(sub).font(.subheadline).foregroundStyle(theme.boardMuted)
                }
                Spacer()
                BigNumber(text: "\(summary.finished.count)", color: theme.highlight, size: 40)
            }
            shelf
            calendar
            HStack(spacing: 14) {
                key(theme.highlight, "Finished a book")
                key(theme.brand, "Read")
            }
        }
        .foregroundStyle(theme.boardText)
        .card(theme.board, radius: 24, padding: 18)
    }

    private var sub: String {
        let last = summary.lastMonthFinished, n = summary.finished.count
        let lastName = Day.monthName(Day.firstOfMonth(now, offset: -1))
        var parts: [String] = []
        if last > 0 || n > 0 { parts.append(n == last ? "same as \(lastName)" : n > last ? "\(n - last) more than \(lastName)" : "\(last - n) fewer than \(lastName)") }
        parts.append("\(summary.pages.formatted()) pages read")
        parts.append(summary.daysLeft > 0 ? "\(summary.daysLeft) \(summary.daysLeft == 1 ? "day" : "days") to go" : "last day of the month")
        return parts.joined(separator: " · ")
    }

    private func height(_ pages: Int) -> CGFloat { 150 + CGFloat(min(1, max(0, Double(pages - 100) / 600))) * 70 }

    private var shelf: some View {
        let colors = [theme.highlight, theme.brand, Color.white, theme.brand.opacity(0.55)]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(summary.finished.enumerated()), id: \.element.id) { i, b in
                    spine(b.title, Day.dayOfMonth(Day.date(b.finishedDay ?? "")).description, fill: colors[i % 4], text: Color(hex: 0x111113), height: height(b.totalPages))
                }
                ForEach(summary.writtenOff) { b in
                    spine(b.title, "DNF", fill: Color(hex: 0x5E5E66), text: .white, height: height(b.totalPages), struck: true)
                }
                ForEach(reading, id: \.0.id) { item in
                    let (b, pct) = item
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6).fill(theme.brand.opacity(0.4)).frame(height: height(b.totalPages) * pct)
                        spine(b.title, "\(Int((pct * 100).rounded()))%", fill: .clear, text: theme.boardText, height: height(b.totalPages))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.boardMuted, lineWidth: 2))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 236, alignment: .bottom)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.boardMuted).frame(height: 5) }
    }

    private func spine(_ title: String, _ badge: String, fill: Color, text: Color, height: CGFloat, struck: Bool = false) -> some View {
        // The title is laid out as a normal line of text the length of the spine (up to two lines),
        // then turned on its side so it reads bottom to top, like a book on a shelf.
        let length = height - 40
        return VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .strikethrough(struck)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .frame(width: length, height: 34, alignment: .leading)
                .rotationEffect(.degrees(-90))
                .frame(width: 34, height: length)
            Text(badge).font(.system(size: 11, weight: .black, design: .rounded))
        }
        .padding(.vertical, 8)
        .frame(width: 46, height: height)
        .foregroundStyle(text)
        .background(fill, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement()
        .accessibilityLabel("\(title), \(badge)")
    }

    private var calendar: some View {
        let mk = Day.monthKey(now)
        let first = Day.firstOfMonth(now)
        let lead = (Day.calendar.component(.weekday, from: first) + 5) % 7
        let days = Day.daysInMonth(now), today = Day.dayOfMonth(now)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).font(.caption2.weight(.bold)).foregroundStyle(theme.boardMuted)
            }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 30) }
            ForEach(1...days, id: \.self) { d in
                let k = "\(mk)-\(String(format: "%02d", d))"
                let fin = summary.finishDays.contains(k), read = summary.readDays.contains(k)
                Text("\(d)")
                    .font(.caption.weight(fin ? .black : .regular)).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(fin || read ? Color(hex: 0x111113) : theme.boardMuted)
                    .background(fin ? theme.highlight : read ? theme.brand : theme.boardGrid, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(d == today ? theme.boardText : .clear, lineWidth: 2))
                    .opacity(d > today ? 0.4 : 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Read on \(summary.readDays.count) days this month")
    }

    private func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10)
            Text(t).font(.caption).foregroundStyle(theme.boardMuted)
        }
    }
}
