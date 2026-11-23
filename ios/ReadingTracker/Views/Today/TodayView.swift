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
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $logTarget) { target in
                LogSessionSheet(books: reading, initialBookID: target.bookID)
                    .environment(\.theme, theme)
            }
            .onChange(of: router.logBookID) { _, id in
                if let id { open(id); router.logBookID = nil }
            }
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

struct ScoreBoard: View {
    let scores: Scores
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    score("Today", "\(scores.today.formatted())", "pages")
                    score("Streak", "\(scores.streak)", scores.streak == 1 ? "day" : "days in a row", highlight: scores.streak > 0)
                }
                GridRow {
                    score("This week", scores.week.formatted(), "pages · " + Stats.versus(scores.week, scores.lastWeekSoFar, "last week"))
                    score("This month", scores.month.formatted(), "pages · " + Stats.versus(scores.month, scores.lastMonthSoFar, "last month"))
                }
            }
            Divider().overlay(theme.boardGrid)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Eyebrow("Finished this month", color: theme.boardMuted)
                BigNumber(text: "\(scores.finishedThisMonth)", color: theme.highlight, size: 30)
                Text((scores.finishedThisMonth == 1 ? "book" : "books") + (scores.dnfThisMonth > 0 ? " · \(scores.dnfThisMonth) written off" : ""))
                    .font(.footnote).foregroundStyle(theme.boardMuted)
            }
        }
        .card(theme.board, radius: 24, padding: 18)
        .foregroundStyle(theme.boardText)
        .accessibilityElement(children: .combine)
    }

    private func score(_ label: String, _ value: String, _ sub: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label, color: theme.boardMuted)
            BigNumber(text: value, color: highlight ? theme.highlight : theme.boardText)
            Text(sub).font(.footnote).foregroundStyle(theme.boardMuted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        default:
            EmptyView()
        }
    }
}
