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
/// Each page is a bold block of colour from the theme, with chunky type, stickers and tilted covers.
struct RecapSlideView: View {
    let slide: RecapSlide
    let recap: Recap
    let covers: [String: Data]
    let theme: AppTheme

    private var ink: Color { Color(hex: 0x111113) }
    private var cream: Color { Color(hex: 0xFFF4E0) }
    private var night: Bool { slide == .habits || slide == .quote || slide == .summary }

    /// Page colour, text colour, and the accent used for big numbers and stickers.
    private var bg: Color {
        switch slide {
        case .intro: return theme.brand
        case .time: return theme.highlight
        case .books, .favourite: return cream
        case .habits, .summary: return ink
        case .quote: return Color(hex: 0x16101F)
        }
    }
    private var fg: Color {
        switch slide {
        case .intro: return theme.onBrand
        case .time: return theme.onHighlight
        case .books, .favourite: return ink
        case .habits, .summary, .quote: return .white
        }
    }
    private var accent: Color {
        switch slide {
        case .intro: return theme.highlight
        case .time: return theme.onHighlight
        case .books, .favourite: return theme.brandText
        case .habits, .summary, .quote: return theme.highlight
        }
    }
    private var muted: Color { fg.opacity(0.62) }

    var body: some View {
        ZStack {
            bg
            decoration
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(recap.period.title.uppercased())
                        .font(.system(size: 11, weight: .black)).tracking(1)
                        .foregroundStyle(bg)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(fg, in: Capsule())
                    Spacer()
                    Text("Pageturner").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(muted)
                }
                content
                Spacer(minLength: 0)
            }
            .padding(26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(fg)
        .clipped()
        .environment(\.colorScheme, night ? .dark : .light)
    }

    /// Shapes behind the text: colour blocks, dots, stars or a soft glow, depending on the page.
    @ViewBuilder private var decoration: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            switch slide {
            case .intro:
                Circle().fill(theme.highlight).frame(width: w * 0.95, height: w * 0.95).position(x: w * 0.12, y: h * 0.93)
                RoundedRectangle(cornerRadius: 40, style: .continuous).fill(theme.onBrand)
                    .frame(width: 180, height: 180).rotationEffect(.degrees(18)).position(x: w * 1.02, y: h * 0.0)
                Burst(points: 4, inner: 0.3).fill(theme.onBrand).frame(width: 34, height: 34).position(x: w * 0.82, y: h * 0.62)
            case .books, .favourite:
                Canvas { ctx, s in
                    var y: CGFloat = 8
                    while y < s.height {
                        var x: CGFloat = 8
                        while x < s.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.6, height: 2.6)), with: .color(Color.black.opacity(0.12)))
                            x += 16
                        }
                        y += 16
                    }
                }
                Burst(points: 7, inner: 0.42).fill(theme.highlight).frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-8)).position(x: w * 0.86, y: h * 0.9)
                Burst(points: 4, inner: 0.3).fill(ink).frame(width: 26, height: 26).position(x: w * 0.66, y: h * 0.95)
            case .time:
                Circle().fill(theme.brand).frame(width: w * 0.8, height: w * 0.8).position(x: w * 0.98, y: h * 0.96)
                Squiggle().stroke(theme.onHighlight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 70, height: 26).position(x: w * 0.78, y: h * 0.16)
            case .habits, .summary:
                Circle().fill(theme.brand).frame(width: w * 0.55, height: w * 0.55).position(x: w * 1.0, y: h * 0.03)
                Burst(points: 4, inner: 0.3).fill(theme.highlight).frame(width: 30, height: 30).position(x: w * 0.7, y: h * 0.07)
            case .quote:
                Canvas { ctx, s in
                    func blob(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: Color, _ o: Double) {
                        let center = CGPoint(x: s.width * x, y: s.height * y), radius = s.width * r
                        ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                                 with: .radialGradient(Gradient(colors: [c.opacity(o), c.opacity(o * 0.45), c.opacity(0)]),
                                                       center: center, startRadius: 0, endRadius: radius))
                    }
                    blob(0.1, 0.08, 0.95, theme.brand, 0.95)
                    blob(1.0, 0.5, 0.9, theme.brandText, 0.8)
                    blob(0.3, 1.02, 0.85, theme.highlight, 0.6)
                    var rng = Seeded(11)
                    for _ in 0..<5200 {
                        let r = CGRect(x: rng.next() * s.width, y: rng.next() * s.height, width: 1, height: 1)
                        ctx.fill(Path(r), with: .color(Color.white.opacity(0.05 + 0.1 * Double(rng.next()))))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func headline(_ text: String) -> some View {
        Text(text).font(.system(size: 34, weight: .black)).fontWidth(.condensed).minimumScaleFactor(0.6)
    }

    /// A white label with a hard shadow, like a sticker.
    private func sticker(_ label: String, _ value: String, tilt: Double = -3) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 10, weight: .black)).tracking(0.8).foregroundStyle(ink.opacity(0.6))
            Text(value).font(.system(size: 16, weight: .black)).foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(night ? theme.brand : ink).offset(x: 5, y: 5)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ink, lineWidth: 2.5)
            }
        )
        .rotationEffect(.degrees(tilt))
    }

    @ViewBuilder private var content: some View {
        switch slide {
        case .intro:
            Spacer(minLength: 0)
            Text("YOUR\n\(recap.period.shortTitle.uppercased())\nIN BOOKS")
                .font(.system(size: 64, weight: .black)).fontWidth(.condensed)
                .minimumScaleFactor(0.4)
            sticker("Swipe", recap.period.isYear ? "A year of turning pages →" : "A month of turning pages →")
                .padding(.top, 6)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        case .books:
            big("\(recap.finished.count)", recap.finished.count == 1 ? "book finished" : "books finished", accent)
            finishedShowcase
                .padding(.top, 10)
            if recap.writtenOff > 0 {
                Text("…and \(recap.writtenOff) you wisely let go.").font(.subheadline.weight(.semibold)).foregroundStyle(muted)
            }
        case .time:
            Spacer(minLength: 0)
            big(recap.pages.formatted(), "pages read", accent)
            if recap.minutes > 0 {
                sticker("Time with a book", "\(recap.hours >= 10 ? "\(Int(recap.hours.rounded()))" : String(format: "%.1f", recap.hours)) hours", tilt: -4)
            }
            sticker("Reading sessions", "\(recap.sessions)", tilt: 3).padding(.leading, 28)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        case .habits:
            Spacer(minLength: 0)
            big("\(recap.readingDays)", "of \(recap.daysElapsed) days you read", theme.highlight)
            big("\(recap.longestStreak)", recap.longestStreak == 1 ? "day: your longest streak" : "days: your longest streak", theme.brand)
            if let best = recap.bestDay {
                sticker("Biggest day", "\(best.pages) pages on \(Day.short(best.day))", tilt: -3)
            }
            if let wd = recap.favouriteWeekday { sticker("Favourite day", wd + "s", tilt: 3).padding(.leading, 28) }
            Spacer(minLength: 0)
        case .favourite:
            if recap.finished.count == 1, let b = recap.finished.first {
                headline(recap.period.isYear ? "BOOK OF THE YEAR" : "BOOK OF THE MONTH").padding(.top, 6)
                singleBook(b)
            } else {
                headline("HIGHLIGHTS").padding(.top, 6)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(highlightRows, id: \.book.id) { row in highlight(row) }
                }
            }
        case .quote:
            if let q = recap.quote {
                Spacer(minLength: 0)
                Text("“\(q.text)”")
                    .font(.system(size: 28, design: .serif)).italic()
                    .minimumScaleFactor(0.35).lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text((q.bookTitle + (q.author.isEmpty ? "" : " · \(q.author)")).uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2.2)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
        case .summary:
            headline("MY \(recap.period.shortTitle.uppercased()) IN BOOKS")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("\(recap.finished.count)", recap.finished.count == 1 ? "book" : "books", theme.highlight, theme.onHighlight)
                tile(recap.pages.formatted(), "pages", theme.brand, theme.onBrand)
                tile(recap.minutes > 0 ? (recap.hours >= 10 ? "\(Int(recap.hours.rounded()))" : String(format: "%.1f", recap.hours)) : "–", "hours", .white, ink)
                tile("\(recap.longestStreak)", "day streak", Color(hex: 0x2A2A30), .white)
                if let avg = recap.averageRating { tile(String(format: "%.1f★", avg), "average rating", Color(hex: 0x2A2A30), .white) }
                tile("\(recap.readingDays)", "reading days", avgTileColor, recap.averageRating == nil ? .white : ink)
            }
            if !recap.finished.isEmpty { shelf.padding(.top, 4) }
        }
    }

    private var avgTileColor: Color { recap.averageRating == nil ? Color(hex: 0x2A2A30) : .white }

    private func big(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: -4) {
            Text(value).font(.system(size: 92, weight: .black)).fontWidth(.condensed)
                .foregroundStyle(color).minimumScaleFactor(0.4).lineLimit(1)
            Text(label).font(.system(size: 19, weight: .heavy))
        }
    }

    /// A bento tile: a block of colour with a big number.
    private func tile(_ value: String, _ label: String, _ fill: Color, _ text: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 38, weight: .black)).fontWidth(.condensed).minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.system(size: 12, weight: .bold)).opacity(0.75)
        }
        .foregroundStyle(text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                if !b.author.isEmpty { Text(b.author).font(.title3).foregroundStyle(muted) }
                if let s = stars(b.rating) { Text(s).font(.title2).foregroundStyle(accent) }
                Text(facts).font(.headline).foregroundStyle(accent)
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
                Text(row.labels.joined(separator: " & ").uppercased()).font(.caption.weight(.heavy)).foregroundStyle(muted)
                Text(row.book.title).font(.headline.weight(.heavy)).lineLimit(2)
                if !row.details.isEmpty {
                    Text(row.details.joined(separator: " · ")).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
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
                    if !b.author.isEmpty { Text(b.author).font(.subheadline).foregroundStyle(muted) }
                    if let stars = stars(b.rating) { Text(stars).font(.title3).foregroundStyle(accent) }
                    if let d = b.finishedDay { Text("Finished \(Day.short(d))").font(.subheadline.weight(.semibold)).foregroundStyle(muted) }
                }
            }
        } else if n <= 3 {
            let w: CGFloat = n == 2 ? 112 : 86
            HStack(alignment: .top, spacing: 14) {
                ForEach(books) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        cover(b, width: w)
                        Text(b.title).font(.caption.weight(.bold)).lineLimit(2).frame(width: w, alignment: .leading)
                        if let stars = stars(b.rating) { Text(stars).font(.caption).foregroundStyle(accent) }
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
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fg.opacity(0.15))
                        Text("+\(n - shown.count)\nmore").font(.system(size: 15, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center).foregroundStyle(fg)
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
                Text("+\(n - shown.count)").font(.headline.weight(.heavy)).foregroundStyle(muted).padding(.leading, 18)
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
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(max(2, width * 0.035))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
        .rotationEffect(.degrees(Double(b.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 7 }) - 3))
    }
}
