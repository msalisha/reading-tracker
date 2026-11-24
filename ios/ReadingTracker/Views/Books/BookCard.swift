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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                NavigationLink(value: book) {
                    HStack(alignment: .top, spacing: 14) {
                        CoverView(data: book.coverData, title: book.title, width: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title).font(.system(.headline, design: .rounded, weight: .bold)).multilineTextAlignment(.leading)
                            if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
                            if book.isAudio { AudioBadge().padding(.top, 2) }
                            Spacer(minLength: 6)
                            Text(pace.position).font(.footnote.weight(.semibold)).monospacedDigit()
                            Text(pace.line).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .trailing, spacing: 10) {
                    Menu {
                        Button { guarded { Library.markFinished(ctx, book); router.rateBookID = book.uid } } label: {
                            Label("Finished it", systemImage: "checkmark.seal")
                        }
                        Button { guarded { askDNF = true } } label: { Label("Did not finish", systemImage: "xmark.circle") }
                        Divider()
                        Button(role: .destructive) { askDelete = true } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline).foregroundStyle(.secondary)
                            .frame(width: 34, height: 34).background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .accessibilityLabel("More for \(book.title)")
                    .accessibilityIdentifier("cardMore")
                    ProgressRing(fraction: pace.fraction, color: theme.brand)
                }
            }

            ProgressBar(fraction: pace.fraction, color: theme.brand, height: 8)
            Sparkline(points: Stats.progressLine(book.snap, sessions: sessions), total: book.totalPages, color: theme.brandText)

            if let t = timer.timer, t.bookID == book.uid {
                CardTimer(timer: t)
            }
            HStack(spacing: 8) {
                if timer.timer == nil {
                    Button {
                        guarded {
                            timer.start(book: book, startPage: book.currentPage)
                            router.tab = .today
                        }
                    } label: { Label("Start timer", systemImage: "play.fill") }
                    .buttonStyle(PillButton(kind: .highlight))
                    .accessibilityIdentifier("cardStartTimer")
                }
                Button { guarded { router.logBookID = book.uid; router.tab = .today } } label: {
                    Label(book.isAudio ? "Log listening" : "Log pages", systemImage: "square.and.pencil")
                }
                .buttonStyle(PillButton(kind: .solid))
            }
        }
        .card(theme.surface, radius: 24, padding: 16)
        .alert("Write off \(book.title)?", isPresented: $askDNF) {
            TextField("Why? (optional)", text: $dnfNote)
            Button("Write it off", role: .destructive) { Library.markDNF(ctx, book, note: dnfNote); dnfNote = "" }
            Button("Keep reading", role: .cancel) {}
        } message: {
            Text(book.isAudio ? "It stops where you are and moves to the shelf. Your listening still counts."
                              : "It stops on page \(book.currentPage) and moves to the shelf. Your pages still count.")
        }
        .confirmationDialog("Delete \(book.title)?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete book and its \(book.sessions?.count ?? 0) sessions", role: .destructive) { Library.delete(ctx, book) }
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
