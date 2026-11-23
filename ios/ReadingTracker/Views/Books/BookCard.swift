import SwiftUI
import SwiftData

/// A book in progress: progress, pace, a little reading line, and the actions.
struct BookCard: View {
    let book: Book
    let sessions: [SessionSnap]

    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(TimerModel.self) private var timer
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @State private var askDNF = false
    @State private var dnfNote = ""
    @State private var askDelete = false

    var body: some View {
        let pace = Stats.pace(book.snap, sessions: sessions, now: .now)
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: book) {
                HStack(alignment: .top, spacing: 12) {
                    CoverView(data: book.coverData, title: book.title, width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.headline).multilineTextAlignment(.leading)
                        if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    Text("\(Int((pace.fraction * 100).rounded()))%").font(.system(.title3, design: .rounded, weight: .black))
                }
            }
            .buttonStyle(.plain)

            ProgressBar(fraction: pace.fraction, color: theme.brand)
            HStack {
                Text("Page \(pace.current.formatted()) of \(book.totalPages.formatted())")
                Spacer()
                Text(pace.line).multilineTextAlignment(.trailing)
            }
            .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            Sparkline(points: Stats.progressLine(book.snap, sessions: sessions), total: book.totalPages, color: theme.brandText)

            HStack(spacing: 8) {
                Button("Log pages") { guarded { router.logBookID = book.uid; router.tab = .today } }
                    .buttonStyle(PillButton(kind: .solid))
                Button("Finished it") { guarded { Library.markFinished(ctx, book); router.rateBookID = book.uid } }
                    .buttonStyle(PillButton(kind: .highlight))
            }

            if let t = timer.timer, t.bookID == book.uid {
                CardTimer(timer: t)
            } else if timer.timer == nil {
                Button("Start timer") {
                    guarded {
                        timer.start(book: book, startPage: book.currentPage)
                        router.tab = .today
                    }
                }
                .buttonStyle(PillButton(kind: .outline))
                .accessibilityIdentifier("cardStartTimer")
            }

            HStack {
                Button("Did not finish") { guarded { askDNF = true } }
                Spacer()
                Button("Delete", role: .destructive) { askDelete = true }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        }
        .card(theme.surface, radius: 18, padding: 16)
        .alert("Write off \(book.title)?", isPresented: $askDNF) {
            TextField("Why? (optional)", text: $dnfNote)
            Button("Write it off", role: .destructive) { Library.markDNF(ctx, book, note: dnfNote); dnfNote = "" }
            Button("Keep reading", role: .cancel) {}
        } message: {
            Text("It stops on page \(book.currentPage) and moves to the shelf. Your pages still count.")
        }
        .confirmationDialog("Delete \(book.title)?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete book and its \(book.sessions.count) sessions", role: .destructive) { Library.delete(ctx, book) }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func guarded(_ action: () -> Void) {
        if store.access.canEdit { action() } else { router.showPaywall = true }
    }
}

/// The running timer on a book's card: live clock, pause or resume, and done.
struct CardTimer: View {
    let timer: ActiveTimer
    @Environment(TimerModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme

    var body: some View {
        let running = timer.status == .running
        VStack(spacing: 10) {
            HStack {
                if running { Circle().fill(theme.highlight).frame(width: 9, height: 9) }
                Eyebrow(running ? "Reading now" : timer.status == .paused ? "Paused" : "Stopped", color: theme.onBrand)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    Text(ActiveTimer.clock(timer.elapsed(at: tl.date)))
                        .font(.system(size: 26, weight: .black, design: .rounded)).monospacedDigit()
                        .opacity(running ? 1 : 0.55)
                }
            }
            HStack(spacing: 8) {
                if running {
                    Button("Pause") { model.pause() }.buttonStyle(PillButton(kind: .solid)).accessibilityIdentifier("cardPause")
                } else {
                    Button("Resume") { model.resume() }.buttonStyle(PillButton(kind: .solid)).accessibilityIdentifier("cardResume")
                }
                Button(running ? "Done" : "Log it") {
                    if running { model.stop() }
                    router.tab = .today
                }
                .buttonStyle(PillButton(kind: .highlight))
            }
        }
        .foregroundStyle(theme.onBrand)
        .padding(12)
        .background(theme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
