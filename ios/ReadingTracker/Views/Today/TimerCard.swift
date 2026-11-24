import SwiftUI
import UIKit
import SwiftData

/// The big reading timer: pick a book, check the starting page, start, pause, then log the page you got to.
struct TimerCard: View {
    let readingBooks: [Book]
    let sessions: [SessionSnap]

    @Environment(TimerModel.self) private var timerModel
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme

    @State private var pickedID = ""
    @State private var fromText = ""
    @State private var toText = ""
    @State private var error: String?
    @FocusState private var fromFocused: Bool
    @FocusState private var toFocused: Bool

    private var timer: ActiveTimer? { timerModel.timer }
    private var timedBook: Book? { timer.flatMap { t in readingBooks.first { $0.uid == t.bookID } ?? Library.book(ctx, uid: t.bookID) } }
    private var pickedBook: Book? { readingBooks.first { $0.uid == pickedID } ?? readingBooks.first }
    private var ink: Color { theme.onBrand }
    /// The book being timed (or about to be) is an audiobook.
    private var isAudio: Bool { (timer != nil ? timedBook : pickedBook)?.isAudio ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if timer?.status == .running {
                    Circle().fill(theme.highlight).frame(width: 9, height: 9).overlay(Circle().stroke(ink, lineWidth: 1.5))
                }
                Eyebrow(isAudio ? "Listening timer" : "Reading timer", color: ink)
            }

            if let t = timer {
                Text(timedBook?.title ?? t.bookTitle).font(.title3.weight(.bold))
            } else if !readingBooks.isEmpty {
                Menu {
                    Picker("Book", selection: $pickedID) {
                        ForEach(readingBooks) { Text($0.title).tag($0.uid) }
                    }
                } label: {
                    HStack {
                        Text(pickedBook?.title ?? "Choose a book").font(.headline).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(Color(hex: 0x111113))
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0x111113), lineWidth: 1.5))
                }
                .accessibilityLabel("Book to time")
                .accessibilityIdentifier("timerBookPicker")
            }

            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(ActiveTimer.clock(timer?.elapsed(at: tl.date) ?? 0))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .opacity(timer == nil || timer?.status == .running ? 1 : 0.55)
                    .accessibilityLabel("Timer")
                    .accessibilityIdentifier("timerClock")
            }

            FocusSoundBar()

            if showFromField {
                PageField(label: isAudio ? (timer == nil ? "Starting at" : "Started at") : (timer == nil ? "Starting on page" : "Started on page"),
                          text: $fromText, placeholder: "0", identifier: "timerFrom", focused: $fromFocused, isAudio: isAudio)
            }
            if let t = timer, t.status != .running, timedBook != nil {
                PageField(label: isAudio ? "Got to" : "Finished on page", text: $toText,
                          placeholder: placeholderTo, identifier: "timerTo", focused: $toFocused, isAudio: isAudio)
            }
            if let t = timer, t.status == .running {
                Text(isAudio ? "From \(Stats.formatMinutes(Double(t.startPage)))" : "From page \(t.startPage)")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }

            if let error {
                Text(error).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x111113))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("timerError")
            }

            actions

            Text(note).font(.footnote.weight(.medium))
        }
        .foregroundStyle(ink)
        .padding(18)
        .background(theme.brand, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear(perform: fillFrom)
        .onChange(of: pickedID) { _, _ in error = nil; fillFrom() }
        .onChange(of: timer?.bookID) { _, _ in fillFrom() }
        .onChange(of: readingBooks.map(\.uid)) { _, _ in if timer == nil { fillFrom() } }
        .onChange(of: fromText) { _, v in
            error = nil
            if timer != nil, let p = Int(trimming: v) { timerModel.setStartPage(p) }
        }
        .onChange(of: router.startTimerBookID) { _, id in
            guard let id, timer == nil else { return }
            router.startTimerBookID = nil
            pickedID = id
            fillFrom()
            start()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let t = timer, t.status != .running, toFocused {
                    Button("Log it", action: logIt).fontWeight(.bold).accessibilityIdentifier("keyboardLogIt")
                }
                Spacer()
                Button("Done") { hideKeyboard() }.accessibilityIdentifier("keyboardDone")
            }
        }
    }

    private var showFromField: Bool {
        guard let t = timer else { return pickedBook != nil }
        return t.status != .running && timedBook != nil
    }

    private var placeholderTo: String {
        guard let b = timedBook, let t = timer, !b.isAudio else { return "" }
        return "\(min(t.startPage + 1, b.totalPages))–\(b.totalPages)"
    }

    private var note: String {
        guard let t = timer else {
            if readingBooks.isEmpty { return "Add a book first, then time your reading." }
            return isAudio ? "Change the start if you're not picking up where you left off. The timer keeps counting even if you close the app."
                : "Change the starting page if you're not picking up where you left off. The timer keeps counting even if you close the app."
        }
        if timedBook == nil { return "The book for this timer was deleted." }
        switch t.status {
        case .running: return "Started \(t.startedAt.formatted(date: .omitted, time: .shortened)). It's on your lock screen too."
        case .paused: return isAudio ? "Paused. Check where you got to and tap Log it, or resume."
                                     : "Paused. Type the page you got to and tap Log it, or resume."
        case .stopped: return isAudio ? "We've filled in where you got to from the time listened. Change it if you listen faster, then tap Log it."
                                      : "Check the starting page, type the page you got to, and tap Log it."
        }
    }

    @ViewBuilder private var actions: some View {
        if let t = timer {
            if timedBook == nil {
                Button("Discard") { discard() }.buttonStyle(PillButton(kind: .outline, big: true))
            } else if t.status == .running {
                HStack(spacing: 8) {
                    Button("Pause") { timerModel.pause(); fillListened() }
                        .buttonStyle(PillButton(kind: .solid, big: true)).accessibilityIdentifier("timerPause")
                    Button("Done") { timerModel.stop(); fillListened(); if !isAudio { toFocused = true } }
                        .buttonStyle(PillButton(kind: .highlight, big: true)).accessibilityIdentifier("timerDone")
                }
            } else {
                HStack(spacing: 8) {
                    Button("Log it", action: logIt)
                        .buttonStyle(PillButton(kind: .highlight, big: true)).accessibilityIdentifier("timerLog")
                    Button("Resume") { timerModel.resume() }
                        .buttonStyle(PillButton(kind: .solid, big: true)).accessibilityIdentifier("timerResume")
                }
                Button("Discard this timer", role: .destructive) { discard() }
                    .font(.footnote.weight(.semibold)).underline().foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Button("Start reading", action: start)
                .buttonStyle(PillButton(kind: .highlight, big: true))
                .disabled(pickedBook == nil)
                .accessibilityIdentifier("timerStart")
        }
    }

    /// For an audiobook, where you got to is where you started plus the time listened (you can change it).
    private func fillListened() {
        guard isAudio, toText.isEmpty, let t = timerModel.timer, let b = timedBook else { return }
        toText = "\(min(b.totalPages, t.startPage + t.minutes()))"
    }

    private func fillFrom() {
        if pickedID.isEmpty || !readingBooks.contains(where: { $0.uid == pickedID }) { pickedID = readingBooks.first?.uid ?? "" }
        if let t = timer {
            fromText = "\(t.startPage)"
        } else if let b = pickedBook {
            fromText = "\(Stats.currentPage(b.snap, sessions: sessions))"
        }
    }

    private func start() {
        guard store.access.canEdit else { router.showPaywall = true; return }
        guard let b = pickedBook else { return }
        if b.totalPages <= 0 {
            error = Library.problem(from: nil, to: nil, totalPages: 0, isAudio: b.isAudio)
            return
        }
        let from = Int(trimming: fromText)
        guard let from, from >= 0, from < b.totalPages else {
            if b.isAudio {
                error = from == nil ? "Enter where you're starting from." : "This audiobook is \(Stats.formatMinutes(Double(b.totalPages))) long, so you need to start before the end."
            } else {
                error = from == nil ? "Type the page you are starting on." : "This book has \(b.totalPages) pages, so you need to start before page \(b.totalPages)."
            }
            fromFocused = true
            return
        }
        error = nil
        toText = ""
        hideKeyboard()
        timerModel.start(book: b, startPage: from)
    }

    private func logIt() {
        guard store.access.canEdit else { router.showPaywall = true; return }
        guard let t = timer, let b = timedBook else { return }
        let from = Int(trimming: fromText), to = Int(trimming: toText)
        if let problem = Library.problem(from: from, to: to, totalPages: b.totalPages, isAudio: b.isAudio) {
            error = problem
            if from == nil || (from ?? 0) >= b.totalPages { fromFocused = true } else { toFocused = true }
            return
        }
        error = nil
        hideKeyboard()
        let finished = Library.logSession(ctx, book: b, startedAt: t.startedAt, from: from!, to: to!, minutes: t.minutes())
        toText = ""
        timerModel.clear()
        if finished { router.rateBookID = b.uid }
    }

    private func hideKeyboard() {
        fromFocused = false
        toFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func discard() {
        toText = ""
        error = nil
        timerModel.clear()
    }
}

/// Off / Rain / Café / Fire, plus a volume slider. Sounds play while the timer runs;
/// choosing one before you start plays a short preview.
struct FocusSoundBar: View {
    @State private var player = FocusSoundPlayer.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(FocusSound.allCases) { s in
                    let on = player.sound == s
                    Button { player.setSound(s) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: s.icon).font(.subheadline.weight(.semibold))
                            Text(s.title).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color(hex: 0x111113))
                        .background(on ? Color(hex: 0x111113) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s.title) sound")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("sound-\(s.rawValue)")
                }
            }
            if player.sound != .off {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption)
                    Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0.05...1)
                        .tint(Color(hex: 0x111113))
                        .accessibilityLabel("Sound volume")
                    Image(systemName: "speaker.wave.3.fill").font(.caption)
                }
            }
        }
    }
}
