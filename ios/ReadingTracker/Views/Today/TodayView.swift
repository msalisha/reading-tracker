import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme
    @Query(sort: \Book.lastAt, order: .reverse) private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @State private var logTarget: LogTarget?

    private var reading: [Book] { books.filter { $0.status == .reading } }

    var body: some View {
        let snaps = sessions.map(\.snap)
        let now = Date()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                            .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                        Text(greeting(now)).font(.system(.largeTitle, design: .rounded, weight: .black))
                    }
                    .padding(.top, 4)
                    TrialBanner()
                    ScoreBoard(scores: Stats.scores(books: books.map(\.snap), sessions: snaps, now: now))
                    TimerCard(readingBooks: reading, sessions: snaps)
                    Button("Log pages without the timer") { open(nil) }
                        .buttonStyle(PillButton(kind: .brand, big: true))
                        .disabled(reading.isEmpty)
                        .accessibilityIdentifier("openLog")
                    SectionTitle(text: "On the go", trailing: reading.isEmpty ? nil : "\(reading.count) in progress")
                    if reading.isEmpty {
                        EmptyCard(text: "Nothing on the go. Head to Books to add one.")
                    }
                    ForEach(reading) { book in
                        Button { open(book.uid) } label: {
                            MiniBookRow(book: book, pace: Stats.pace(book.snap, sessions: snaps, now: now))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("") } }   // the greeting is the title
            .sheet(item: $logTarget) { target in
                LogSessionSheet(books: reading, initialBookID: target.bookID)
                    .environment(\.theme, theme)
            }
            .onChange(of: router.logBookID) { _, id in
                if let id { open(id); router.logBookID = nil }
            }
        }
    }

    private func greeting(_ now: Date) -> String {
        switch Day.calendar.component(.hour, from: now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func open(_ bookID: String?) {
        guard store.access.canEdit else { router.showPaywall = true; return }
        logTarget = LogTarget(bookID: bookID ?? reading.first?.uid ?? "")
    }
}

private struct LogTarget: Identifiable {
    let bookID: String
    var id: String { bookID }
}

/// Today's numbers as a bento grid: the streak and today lead, then the week, the month and books finished.
struct ScoreBoard: View {
    let scores: Scores
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                tile("Streak", "flame.fill", "\(scores.streak)", scores.streak == 1 ? "day in a row" : "days in a row",
                     fill: scores.streak > 0 ? theme.highlight : theme.surface,
                     text: scores.streak > 0 ? theme.onHighlight : Color.primary, big: true)
                tile("Today", "book.fill", scores.today.formatted(), scores.today == 1 ? "page" : "pages",
                     fill: theme.board, text: theme.boardText, big: true)
            }
            HStack(spacing: 10) {
                tile("This week", "calendar", scores.week.formatted(), Stats.versus(scores.week, scores.lastWeekSoFar, "last week"),
                     fill: theme.surface, text: Color.primary)
                tile("This month", "chart.bar.fill", scores.month.formatted(), Stats.versus(scores.month, scores.lastMonthSoFar, "last month"),
                     fill: theme.surface, text: Color.primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.headline)
                Text("Finished this month").font(.subheadline.weight(.bold))
                Spacer()
                BigNumber(text: "\(scores.finishedThisMonth)", color: theme.onBrand, size: 28)
                Text((scores.finishedThisMonth == 1 ? "book" : "books") + (scores.dnfThisMonth > 0 ? " · \(scores.dnfThisMonth) written off" : ""))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(theme.onBrand)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(theme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ label: String, _ icon: String, _ value: String, _ sub: String,
                      fill: Color, text: Color, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
            }
            .opacity(0.7)
            BigNumber(text: value, color: text, size: big ? 46 : 32)
            Text(sub).font(.footnote.weight(.medium)).opacity(0.7).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct MiniBookRow: View {
    let book: Book
    let pace: Pace
    @Environment(\.theme) private var theme
    @Environment(TimerModel.self) private var timer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(data: book.coverData, title: book.title, width: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(book.title).font(.headline).multilineTextAlignment(.leading)
                    Spacer()
                    Text("\(Int((pace.fraction * 100).rounded()))%").font(.system(.headline, design: .rounded, weight: .black))
                }
                ProgressBar(fraction: pace.fraction, color: theme.brand, height: 8)
                Text("Page \(pace.current.formatted()) of \(book.totalPages.formatted()) · \(pace.line)")
                    .font(.footnote).foregroundStyle(.secondary)
                if let t = timer.timer, t.bookID == book.uid {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text((t.status == .running ? "Timer running · " : "Timer paused · ") + ActiveTimer.clock(t.elapsed(at: ctx.date)))
                            .font(.footnote.weight(.bold)).monospacedDigit().foregroundStyle(theme.brandText)
                    }
                }
            }
        }
        .card(theme.surface, radius: 16, padding: 14)
        .contentShape(Rectangle())
        .accessibilityHint("Log pages for this book")
    }
}

struct EmptyCard: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5])).foregroundStyle(Color(.systemGray4)))
    }
}

/// Trial countdown, or a nudge to unlock once it's over.
struct TrialBanner: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme

    var body: some View {
        switch store.access {
        case .trial(let end):
            Button { router.showPaywall = true } label: {
                HStack {
                    Image(systemName: "gift")
                    Text("Free trial · \(AccessRules.timeLeft(until: end, now: store.now))")
                    Spacer()
                    Text("Unlock").fontWeight(.bold)
                }
                .font(.subheadline)
                .card(theme.surface, radius: 14, padding: 12)
            }
            .buttonStyle(.plain)
        case .expired:
            Button { router.showPaywall = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your free trial has ended").font(.headline)
                    Text("Everything you've logged is still here. Unlock to keep adding books and sessions.").font(.subheadline)
                }
                .foregroundStyle(theme.onBrand)
                .card(theme.brand, radius: 16, padding: 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trialEnded")
        case .noTrial:
            Button { router.showPaywall = true } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start your 3-day free trial").font(.headline)
                    Text("You're looking around. Start the free trial to add books, time your reading and log pages.").font(.subheadline)
                }
                .foregroundStyle(theme.onBrand)
                .card(theme.brand, radius: 16, padding: 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trialNotStarted")
        default:
            EmptyView()
        }
    }
}
