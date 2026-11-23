import SwiftUI
import SwiftData
import UIKit

/// "Your November in books" / "Your 2026 in books": swipe through story-style slides and share any of them as a picture.
struct RecapView: View {
    @State var period: Recap.Period

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Query private var books: [Book]
    @Query private var sessions: [ReadingSession]
    @Query private var notes: [BookNote]
    @State private var page = 0
    @State private var shareImage: UIImage?

    private var covers: [String: Data] {
        var m: [String: Data] = [:]
        for b in books { if let c = b.coverData { m[b.uid] = c } }
        return m
    }

    private var recap: Recap {
        Recap.make(period, books: books.map(\.snap), sessions: sessions.map(\.snap),
                   notes: notes.map { Recap.NoteInput(text: $0.text, isQuote: $0.kind == .quote, day: Day.key($0.createdAt),
                                                      bookTitle: $0.book?.title ?? "", author: $0.book?.author ?? "") },
                   now: .now)
    }

    var body: some View {
        let r = recap
        let slides = RecapSlide.slides(for: r)
        NavigationStack {
            VStack(spacing: 14) {
                if r.isEmpty {
                    ContentUnavailableView("Nothing logged in \(period.title) yet", systemImage: "book.closed",
                                           description: Text("Log some reading and your recap will fill in."))
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(slides.enumerated()), id: \.offset) { item in
                            RecapSlideView(slide: item.element, recap: r, covers: covers, theme: theme)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .padding(.horizontal, 20)
                                .tag(item.offset)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .accessibilityIdentifier("recapSlides")

                    if let shareImage {
                        ShareLink(item: Image(uiImage: shareImage),
                                  preview: SharePreview("My \(period.title) in books", image: Image(uiImage: shareImage))) {
                            Label("Share this page", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PillButton(kind: .brand, big: true))
                        .padding(.horizontal, 20)
                        .accessibilityIdentifier("recapShare")
                    }
                }
            }
            .padding(.bottom, 12)
            .navigationTitle(period.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        let now = Date()
                        Button("This month") { choose(.thisMonth(now)) }
                        Button("Last month") { choose(.lastMonth(now)) }
                        Button("This year") { choose(.thisYear(now)) }
                        Button("Last year") { choose(.lastYear(now)) }
                    } label: { Label("Choose period", systemImage: "calendar") }
                }
            }
            .onAppear { render(slides, r) }
            .onChange(of: page) { _, _ in render(slides, r) }
            .onChange(of: period) { _, _ in render(RecapSlide.slides(for: recap), recap) }
        }
    }

    private func choose(_ p: Recap.Period) {
        page = 0
        period = p
    }

    /// Draws the current slide as a 1080 × 1920 picture for sharing.
    @MainActor private func render(_ slides: [RecapSlide], _ r: Recap) {
        guard !slides.isEmpty, !r.isEmpty else { shareImage = nil; return }
        let slide = slides[min(page, slides.count - 1)]
        let view = RecapSlideView(slide: slide, recap: r, covers: covers, theme: theme)
            .frame(width: 360, height: 640)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

enum RecapSlide: Hashable {
    case intro, books, time, habits, favourite, quote, summary

    static func slides(for r: Recap) -> [RecapSlide] {
        var s: [RecapSlide] = [.intro]
        if !r.finished.isEmpty { s.append(.books) }
        if r.pages > 0 { s.append(.time); s.append(.habits) }
        if r.topBook != nil || r.longestBook != nil { s.append(.favourite) }
        if r.quote != nil { s.append(.quote) }
        s.append(.summary)
        return s
    }
}

/// One slide. Takes everything it needs as plain values, so it can also be drawn into a picture.
struct RecapSlideView: View {
    let slide: RecapSlide
    let recap: Recap
    let covers: [String: Data]
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 5) {
                Capsule().fill(theme.brand).frame(width: 40, height: 7)
                Capsule().fill(theme.highlight).frame(width: 26, height: 7)
                Capsule().fill(theme.boardMuted).frame(width: 14, height: 7)
                Spacer()
                Text(recap.period.title.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(theme.boardMuted)
            }
            content
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("Pageturner").font(.caption.weight(.heavy)).foregroundStyle(theme.boardMuted)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.board)
        .foregroundStyle(theme.boardText)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch slide {
        case .intro:
            Spacer(minLength: 0)
            Text("Your \(recap.period.shortTitle) in books")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5)
            Text(recap.period.isYear ? "A year of turning pages. Swipe to see it." : "A month of turning pages. Swipe to see it.")
                .font(.title3.weight(.medium)).foregroundStyle(theme.boardMuted)
        case .books:
            big("\(recap.finished.count)", recap.finished.count == 1 ? "book finished" : "books finished", theme.highlight)
            shelf
            if recap.writtenOff > 0 {
                Text("…and \(recap.writtenOff) you wisely let go.").font(.subheadline).foregroundStyle(theme.boardMuted)
            }
        case .time:
            big(recap.pages.formatted(), "pages read", theme.brand)
            if recap.minutes > 0 {
                big(recap.hours >= 10 ? "\(Int(recap.hours.rounded()))" : String(format: "%.1f", recap.hours), "hours with a book", theme.highlight)
            }
            Text("Across \(recap.sessions) reading \(recap.sessions == 1 ? "session" : "sessions").")
                .font(.title3.weight(.medium)).foregroundStyle(theme.boardMuted)
        case .habits:
            big("\(recap.readingDays)", "of \(recap.daysElapsed) days you read", theme.brand)
            big("\(recap.longestStreak)", recap.longestStreak == 1 ? "day: your longest streak" : "days: your longest streak", theme.highlight)
            if let best = recap.bestDay {
                line("Biggest day", "\(best.pages) pages on \(Day.short(best.day))")
            }
            if let wd = recap.favouriteWeekday { line("Favourite reading day", wd + "s") }
        case .favourite:
            if let top = recap.topBook {
                Text("Top rated").font(.headline).foregroundStyle(theme.boardMuted)
                bookFeature(top, caption: top.rating.map { String(repeating: "★", count: Int($0)) + ($0.truncatingRemainder(dividingBy: 1) > 0 ? "½" : "") })
            }
            if let long = recap.longestBook, long.id != recap.topBook?.id || recap.topBook == nil {
                Text("Longest read").font(.headline).foregroundStyle(theme.boardMuted).padding(.top, 6)
                bookFeature(long, caption: "\(long.totalPages.formatted()) pages")
            }
            if let fast = recap.fastest {
                line("Fastest finish", "\(fast.book.title) in \(fast.days) \(fast.days == 1 ? "day" : "days")")
            }
        case .quote:
            if let q = recap.quote {
                Spacer(minLength: 0)
                Text("“").font(.system(size: 80, weight: .black, design: .serif)).foregroundStyle(theme.highlight).frame(height: 40, alignment: .top)
                Text(q.text).font(.system(size: 26, weight: .semibold, design: .serif)).minimumScaleFactor(0.35).lineSpacing(5)
                Text(q.bookTitle + (q.author.isEmpty ? "" : " · \(q.author)")).font(.headline).foregroundStyle(theme.brand)
            }
        case .summary:
            Text("My \(recap.period.shortTitle) in books").font(.system(size: 30, weight: .black, design: .rounded)).minimumScaleFactor(0.6)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 18) {
                tile("\(recap.finished.count)", recap.finished.count == 1 ? "book" : "books", theme.highlight)
                tile(recap.pages.formatted(), "pages", theme.brand)
                tile(recap.minutes > 0 ? (recap.hours >= 10 ? "\(Int(recap.hours.rounded()))" : String(format: "%.1f", recap.hours)) : "–", "hours", theme.boardText)
                tile("\(recap.longestStreak)", "day streak", theme.boardText)
                if let avg = recap.averageRating { tile(String(format: "%.1f★", avg), "average rating", theme.boardText) }
                tile("\(recap.readingDays)", "reading days", theme.boardText)
            }
            if !recap.finished.isEmpty { shelf }
        }
    }

    private func big(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.title3.weight(.semibold))
        }
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.subheadline).foregroundStyle(theme.boardMuted)
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(theme.boardMuted)
            Text(value).font(.title3.weight(.bold))
        }
    }

    private func bookFeature(_ b: BookSnap, caption: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            cover(b, width: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(b.title).font(.title3.weight(.heavy)).lineLimit(3)
                if !b.author.isEmpty { Text(b.author).font(.subheadline).foregroundStyle(theme.boardMuted) }
                if let caption { Text(caption).font(.headline).foregroundStyle(theme.highlight) }
            }
        }
    }

    /// Covers of the finished books, overlapping like a fanned-out pile.
    private var shelf: some View {
        let shown = Array(recap.finished.suffix(12))
        return HStack(spacing: shown.count > 6 ? -18 : 8) {
            ForEach(shown) { b in cover(b, width: shown.count > 6 ? 46 : 54) }
        }
    }

    @ViewBuilder private func cover(_ b: BookSnap, width: CGFloat) -> some View {
        Group {
            if let data = covers[b.id], let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.brand
                    Text(b.title)
                        .font(.system(size: width * 0.16, weight: .heavy))
                        .foregroundStyle(theme.onBrand)
                        .multilineTextAlignment(.center)
                        .padding(4)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.board, lineWidth: 2))
    }
}
