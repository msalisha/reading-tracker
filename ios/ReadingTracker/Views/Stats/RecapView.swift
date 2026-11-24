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
    /// "Auto" picks a matching background for each page; otherwise one style for every page.
    @AppStorage("recapBackground") private var backgroundRaw = "Auto"

    private var chosen: CardBackground? { CardBackground(rawValue: backgroundRaw) }

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
                            RecapSlideView(slide: item.element, recap: r, covers: covers, theme: theme, background: chosen)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .padding(.horizontal, 20)
                                .tag(item.offset)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityIdentifier("recapSlides")

                    // page dots below the card, so they don't sit on top of the artwork
                    HStack(spacing: 7) {
                        ForEach(0..<slides.count, id: \.self) { i in
                            Circle()
                                .fill(i == page ? theme.brandText : Color.secondary.opacity(0.3))
                                .frame(width: i == page ? 8 : 7, height: i == page ? 8 : 7)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Page \(page + 1) of \(slides.count)")

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
                        Picker("Background", selection: $backgroundRaw) {
                            Label("Matching each page", systemImage: "wand.and.stars").tag("Auto")
                            ForEach(CardBackground.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0.rawValue) }
                        }
                    } label: { Label("Background", systemImage: "paintbrush") }
                    .accessibilityIdentifier("recapBackground")
                }
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
            .onChange(of: backgroundRaw) { _, _ in render(slides, r) }
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
        let view = RecapSlideView(slide: slide, recap: r, covers: covers, theme: theme, background: chosen)
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
    /// nil = the matching background for this page.
    var background: CardBackground? = nil

    /// Each page gets a background that suits it.
    private var style: CardBackground {
        if let background { return background }
        switch slide {
        case .intro: return .glow
        case .books: return recap.finished.count <= 6 ? .shelf : .glow
        case .time: return .paper
        case .habits: return .glow
        case .favourite: return .openBook
        case .quote: return .paper
        case .summary: return recap.finished.isEmpty ? .glow : .confetti
        }
    }

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
        .background(CardBackdrop(style: style, theme: theme))
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
            Spacer(minLength: 0)
            big("\(recap.finished.count)", recap.finished.count == 1 ? "book finished" : "books finished", theme.highlight)
            finishedShowcase
                .padding(.top, 6)
            if recap.writtenOff > 0 {
                Text("…and \(recap.writtenOff) you wisely let go.").font(.subheadline).foregroundStyle(theme.boardMuted)
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        case .time:
            Spacer(minLength: 0)
            big(recap.pages.formatted(), "pages read", theme.brand)
            if recap.minutes > 0 {
                big(recap.hours >= 10 ? "\(Int(recap.hours.rounded()))" : String(format: "%.1f", recap.hours), "hours with a book", theme.highlight)
            }
            Text("Across \(recap.sessions) reading \(recap.sessions == 1 ? "session" : "sessions").")
                .font(.title3.weight(.medium)).foregroundStyle(theme.boardMuted)
        case .habits:
            Spacer(minLength: 0)
            big("\(recap.readingDays)", "of \(recap.daysElapsed) days you read", theme.brand)
            big("\(recap.longestStreak)", recap.longestStreak == 1 ? "day: your longest streak" : "days: your longest streak", theme.highlight)
            if let best = recap.bestDay {
                line("Biggest day", "\(best.pages) pages on \(Day.short(best.day))")
            }
            if let wd = recap.favouriteWeekday { line("Favourite reading day", wd + "s") }
        case .favourite:
            if recap.finished.count == 1, let b = recap.finished.first {
                Text(recap.period.isYear ? "Book of the year" : "Book of the month")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .padding(.top, 8)
                singleBook(b)
            } else {
                Text("Highlights").font(.system(size: 30, weight: .black, design: .rounded)).padding(.top, 8)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(highlightRows, id: \.book.id) { row in highlight(row) }
                }
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

    /// One finished book, shown large: cover, title, author, rating, and how long it took.
    private func singleBook(_ b: BookSnap) -> some View {
        let days = recap.fastest.flatMap { $0.book.id == b.id ? $0.days : nil }
        let facts = ["\(b.totalPages.formatted()) pages", days.map { "read in \($0) \($0 == 1 ? "day" : "days")" }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 16) {
            cover(b, width: 132)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(b.title).font(.system(size: 26, weight: .heavy)).lineLimit(3).minimumScaleFactor(0.7)
                if !b.author.isEmpty { Text(b.author).font(.title3).foregroundStyle(theme.boardMuted) }
                if let s = stars(b.rating) { Text(s).font(.title2).foregroundStyle(theme.highlight) }
                Text(facts).font(.headline).foregroundStyle(theme.highlight)
            }
        }
    }

    private struct HighlightRow {
        var book: BookSnap
        var labels: [String]
        var details: [String]
    }

    /// Top rated, longest and fastest, with each book shown once (its facts combined if it wins twice).
    private var highlightRows: [HighlightRow] {
        var rows: [HighlightRow] = []
        func add(_ label: String, _ book: BookSnap?, _ detail: String?) {
            guard let book else { return }
            if let i = rows.firstIndex(where: { $0.book.id == book.id }) {
                rows[i].labels.append(label.lowercased())
                if let detail { rows[i].details.append(detail) }
            } else {
                rows.append(HighlightRow(book: book, labels: [label], details: detail.map { [$0] } ?? []))
            }
        }
        add("Top rated", recap.topBook, stars(recap.topBook?.rating))
        add("Longest read", recap.longestBook, recap.longestBook.map { "\($0.totalPages.formatted()) pages" })
        add("Fastest finish", recap.fastest?.book, recap.fastest.map { "in \($0.days) \($0.days == 1 ? "day" : "days")" })
        return rows
    }

    private func highlight(_ row: HighlightRow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            cover(row.book, width: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.labels.joined(separator: " & ").uppercased()).font(.caption.weight(.heavy)).foregroundStyle(theme.boardMuted)
                Text(row.book.title).font(.headline.weight(.heavy)).lineLimit(2)
                if !row.details.isEmpty {
                    Text(row.details.joined(separator: " · ")).font(.subheadline.weight(.semibold)).foregroundStyle(theme.highlight)
                }
            }
        }
    }

    /// Covers of the finished books, overlapping like a fanned-out pile.
    /// The books finished, sized to how many there are so the page always looks full but not crowded.
    @ViewBuilder private var finishedShowcase: some View {
        let books = recap.finished
        let n = books.count
        if n == 1, let b = books.first {
            HStack(alignment: .bottom, spacing: 18) {
                cover(b, width: 128)
                VStack(alignment: .leading, spacing: 6) {
                    Text(b.title).font(.title2.weight(.heavy)).lineLimit(4).minimumScaleFactor(0.7)
                    if !b.author.isEmpty { Text(b.author).font(.subheadline).foregroundStyle(theme.boardMuted) }
                    if let stars = stars(b.rating) { Text(stars).font(.title3).foregroundStyle(theme.highlight) }
                    if let d = b.finishedDay { Text("Finished \(Day.short(d))").font(.subheadline.weight(.semibold)).foregroundStyle(theme.boardMuted) }
                }
            }
        } else if n <= 3 {
            let w: CGFloat = n == 2 ? 112 : 86
            HStack(alignment: .top, spacing: 14) {
                ForEach(books) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        cover(b, width: w)
                        Text(b.title).font(.caption.weight(.bold)).lineLimit(2).frame(width: w, alignment: .leading)
                        if let stars = stars(b.rating) { Text(stars).font(.caption).foregroundStyle(theme.highlight) }
                    }
                }
            }
        } else {
            let shown = Array(books.suffix(n > 12 ? 11 : 12))
            let columns = n <= 6 ? 3 : 4
            let w: CGFloat = n <= 6 ? 78 : 58
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: 12, alignment: .leading), count: columns),
                      alignment: .leading, spacing: 12) {
                ForEach(shown) { b in cover(b, width: w) }
                if n > 12 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.boardGrid)
                        Text("+\(n - shown.count)\nmore").font(.system(size: 15, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center).foregroundStyle(theme.boardText)
                    }
                    .frame(width: w, height: w * 1.5)
                }
            }
        }
    }

    private func stars(_ rating: Double?) -> String? {
        guard let r = rating, r > 0 else { return nil }
        return String(repeating: "★", count: Int(r)) + (r.truncatingRemainder(dividingBy: 1) > 0 ? "½" : "")
    }

    /// A compact row of covers for the summary page.
    private var shelf: some View {
        let n = recap.finished.count
        let shown = Array(recap.finished.suffix(n > 8 ? 8 : n))
        let w: CGFloat = n <= 4 ? 58 : 44
        return HStack(spacing: n > 5 ? -12 : 8) {
            ForEach(shown) { b in cover(b, width: w) }
            if n > shown.count {
                Text("+\(n - shown.count)").font(.headline.weight(.heavy)).foregroundStyle(theme.boardMuted).padding(.leading, 18)
            }
        }
    }

    @ViewBuilder private func cover(_ b: BookSnap, width: CGFloat) -> some View {
        Group {
            if let data = covers[b.id], let img = UIImage(data: data) {
                FittedCover(image: img)
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
