import SwiftUI
import UIKit

/// The look of a shareable card. Each style is a complete layout, drawn in the chosen colour scheme.
enum CardStyle: String, CaseIterable, Identifiable {
    case poster = "Poster"
    case collage = "Collage"
    case dreamy = "Dreamy"
    case highlighter = "Highlighter"
    case editorial = "Editorial"
    case bookmark = "Bookmark"

    var id: String { rawValue }
    /// Paper-like styles read the theme's light colours; night-like ones its dark colours.
    var scheme: ColorScheme { self == .dreamy || self == .bookmark ? .dark : .light }
}

/// A quote (or thought) laid out as a shareable picture.
struct QuoteCard: View {
    enum Shape: String, CaseIterable, Identifiable {
        case square = "Square", portrait = "Portrait", story = "Story"
        var id: String { rawValue }
        /// Points; rendered at 3× (1080 px wide).
        var size: CGSize {
            switch self {
            case .square: return CGSize(width: 360, height: 360)
            case .portrait: return CGSize(width: 360, height: 450)
            case .story: return CGSize(width: 360, height: 640)
            }
        }
    }

    let text: String
    let isQuote: Bool
    let title: String
    let author: String
    let page: Int?
    let theme: AppTheme
    let shape: Shape
    var style: CardStyle = .poster
    var cover: UIImage? = nil
    var date: Date = .now

    private var w: CGFloat { shape.size.width }
    private var h: CGFloat { shape.size.height }
    private var ink: Color { Color(hex: 0x111113) }
    private var byline: String {
        [author.isEmpty ? nil : author, page.map { "p. \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    private var quoted: String { isQuote ? "“\(text)”" : text }

    /// A starting type size that suits the length of the text and the card; the text still shrinks to fit.
    private func size(_ big: CGFloat, _ small: CGFloat) -> CGFloat {
        let room = Double(h / 450)
        let n = Double(max(text.count, 1))
        let t = min(1, max(0, (n - 40) / 220))
        return (big - (big - small) * CGFloat(t)) * CGFloat(min(1.25, max(0.82, room)))
    }

    var body: some View {
        Group {
            switch style {
            case .poster: poster
            case .collage: collage
            case .dreamy: dreamy
            case .highlighter: highlighter
            case .editorial: editorial
            case .bookmark: bookmark
            }
        }
        .frame(width: w, height: h)
        .clipped()
        .environment(\.colorScheme, style.scheme)
    }

    private func mark(_ color: Color) -> some View {
        Text("Pageturner").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(color)
    }

    // MARK: 1. Poster

    private var posterText: AttributedString {
        var a = AttributedString(text.uppercased())
        let words = text.uppercased().split { !$0.isLetter }.map(String.init)
        if let longest = words.max(by: { $0.count < $1.count }), longest.count >= 4, let r = a.range(of: longest) {
            a[r].swiftUI.backgroundColor = theme.onBrand
            a[r].swiftUI.foregroundColor = theme.brand
        }
        return a
    }

    private var poster: some View {
        ZStack {
            theme.brand
            Circle().fill(theme.highlight).frame(width: w * 0.85, height: w * 0.85)
                .offset(x: -w * 0.33, y: h * 0.5 - w * 0.2)
            RoundedRectangle(cornerRadius: 36, style: .continuous).fill(theme.onBrand)
                .frame(width: 170, height: 170).rotationEffect(.degrees(18))
                .offset(x: w * 0.5 + 6, y: -h * 0.5 - 12)
            VStack(alignment: .leading, spacing: 0) {
                if isQuote {
                    Text("“").font(.system(size: 96, weight: .black)).foregroundStyle(theme.onBrand)
                        .frame(height: 50, alignment: .top)
                }
                Text(posterText)
                    .font(.system(size: size(52, 26), weight: .black))
                    .fontWidth(.condensed)
                    .foregroundStyle(theme.onBrand)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 6)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .black)).lineLimit(2)
                        if !byline.isEmpty { Text(byline).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink).offset(x: 5, y: 5)
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ink, lineWidth: 2.5)
                        }
                    )
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: w * 0.68, alignment: .leading)
                    Spacer(minLength: 8)
                    mark(theme.onBrand)
                }
                .padding(.top, 14)
            }
            .padding(24)
        }
    }

    // MARK: 2. Collage

    private var collage: some View {
        let coverW = min(w * 0.36, h * 0.26)
        return ZStack {
            Color(hex: 0xFFF4E0)
            Canvas { ctx, s in
                var y: CGFloat = 8
                while y < s.height {
                    var x: CGFloat = 8
                    while x < s.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.6, height: 2.6)), with: .color(Color.black.opacity(0.13)))
                        x += 16
                    }
                    y += 16
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Burst(points: 7, inner: 0.42).fill(theme.brand)
                            .frame(width: coverW * 0.66, height: coverW * 0.66).rotationEffect(.degrees(-8))
                        Text(isQuote ? "quote of the day" : "note to self")
                            .font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(ink, in: Capsule())
                            .rotationEffect(.degrees(-5))
                        HStack(spacing: 10) {
                            Squiggle().stroke(ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                .frame(width: 56, height: 22)
                            Burst(points: 4, inner: 0.3).fill(ink).frame(width: 24, height: 24)
                        }
                        .padding(.top, 4).padding(.leading, 18)
                    }
                    Spacer(minLength: 8)
                    ZStack(alignment: .top) {
                        CardCover(image: cover, title: title, theme: theme, width: coverW)
                            .padding(5).background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
                        Rectangle().fill(theme.highlight.opacity(0.7)).frame(width: coverW * 0.55, height: 20)
                            .rotationEffect(.degrees(-6)).offset(y: -10)
                    }
                    .rotationEffect(.degrees(7))
                    .padding(.trailing, 8).padding(.top, 6)
                }
                Spacer(minLength: 10)
                Text(text)
                    .font(.system(size: size(24, 15), weight: .heavy))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: h * 0.36, alignment: .leading)
                    .padding(18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(theme.brand).offset(x: 6, y: 6)
                            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white)
                            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(ink, lineWidth: 2.5)
                        }
                    )
                HStack {
                    Text(byline.isEmpty ? title : byline).font(.system(size: 12, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                    Spacer()
                    mark(ink)
                }
                .padding(.top, 16)
            }
            .padding(22)
        }
    }

    // MARK: 3. Dreamy

    private var dreamy: some View {
        let coverW = min(w * 0.28, h * 0.2)
        return ZStack {
            Color(hex: 0x16101F)
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
                // film grain
                var rng = Seeded(11)
                for _ in 0..<5200 {
                    let r = CGRect(x: rng.next() * s.width, y: rng.next() * s.height, width: 1, height: 1)
                    ctx.fill(Path(r), with: .color(Color.white.opacity(0.05 + 0.1 * Double(rng.next()))))
                }
            }
            VStack(spacing: 0) {
                CardCover(image: cover, title: title, theme: theme, width: coverW)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 14)
                    .padding(.top, 10)
                Text(quoted)
                    .font(.system(size: size(27, 16), weight: .regular, design: .serif)).italic()
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 14)
                Text([title, author].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2.2)
                    .foregroundStyle(.white.opacity(0.92)).lineLimit(2).multilineTextAlignment(.center)
                mark(.white.opacity(0.7)).padding(.top, 12)
            }
            .padding(28)
        }
    }

    // MARK: 4. Highlighter

    private var highlighted: AttributedString {
        var a = AttributedString(quoted)
        a.swiftUI.backgroundColor = theme.highlight.opacity(0.78)
        return a
    }

    private func fauxLines(_ widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, f in
                Capsule().fill(Color(hex: 0x2A2620).opacity(0.13)).frame(width: (w - 78) * f, height: 5)
            }
        }
    }

    private var highlighter: some View {
        let grey = Color(hex: 0x8A8170)
        return ZStack(alignment: .leading) {
            Color(hex: 0xFBF6EA)
            LinearGradient(colors: [Color.black.opacity(0.13), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title.uppercased()).lineLimit(1)
                    Spacer(minLength: 12)
                    Text(author.uppercased()).lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium, design: .serif)).tracking(1.8).foregroundStyle(grey)
                fauxLines(shape == .square ? [1, 0.62] : [1, 0.94, 0.55]).padding(.top, 18)
                Text(highlighted)
                    .font(.system(size: size(27, 16), design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(Color(hex: 0x2A2620))
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                HStack(alignment: .top) {
                    fauxLines([0.52, 0.3])
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 2) {
                        NoteArrow().stroke(theme.brandText, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 34, height: 22)
                        Text(isQuote ? "so true!" : "note to self")
                            .font(.custom("BradleyHandITCTT-Bold", size: 19))
                            .foregroundStyle(theme.brandText)
                    }
                    .rotationEffect(.degrees(-7))
                }
                ZStack {
                    if let page { Text("\(page)").font(.system(size: 11, design: .serif)).foregroundStyle(grey) }
                    HStack { Spacer(); mark(grey) }
                }
                .padding(.top, 16)
            }
            .padding(.leading, 44).padding(.trailing, 30).padding(.vertical, 26)
        }
    }

    // MARK: 5. Editorial

    private var editorial: some View {
        ZStack {
            Color(hex: 0xF4F2EE)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(isQuote ? "QUOTE" : "NOTE")  —  \(date.formatted(.dateTime.day().month(.abbreviated).year()).uppercased())")
                        .font(.system(size: 9, weight: .bold)).tracking(2.2)
                    Spacer()
                    Circle().fill(theme.brand).frame(width: 13, height: 13)
                }
                Text(text)
                    .font(.system(size: size(36, 18), design: .serif))
                    .minimumScaleFactor(0.3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, shape == .square ? 22 : 40).padding(.bottom, 14)
                Rectangle().fill(ink).frame(height: 1.5)
                HStack(spacing: 14) {
                    CardCover(image: cover, title: title, theme: theme, width: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1.4).lineLimit(2)
                        if !byline.isEmpty {
                            Text(byline.uppercased()).font(.system(size: 10, weight: .regular)).tracking(1.4).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    mark(ink)
                }
                .padding(.top, 14)
            }
            .foregroundStyle(ink)
            .padding(28)
        }
    }

    // MARK: 6. Bookmark

    private var bookmark: some View {
        let night = Color(hex: 0x111113)
        let side = w * 0.11, top: CGFloat = 26
        let notchY = (h - top * 2) * 0.72
        return ZStack {
            night
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.highlight)
                // punched notches on both edges, and the hole for the ribbon
                Circle().fill(night).frame(width: 26, height: 26).offset(x: -(w - side * 2) / 2, y: notchY - 13)
                Circle().fill(night).frame(width: 26, height: 26).offset(x: (w - side * 2) / 2, y: notchY - 13)
                Circle().fill(night).frame(width: 22, height: 22).offset(y: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(quoted)
                        .font(.system(size: size(31, 16), weight: .black))
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 62).padding(.bottom, 10)
                        .frame(height: notchY - 6, alignment: .top)
                    DashedRule().stroke(theme.onHighlight, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                        .frame(height: 2.5).padding(.top, 5)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.system(size: 13, weight: .black)).lineLimit(2)
                            if !byline.isEmpty { Text(byline).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
                        }
                        Spacer(minLength: 8)
                        Text("\(isQuote ? "READ" : "NOTED")\n\(date.formatted(.dateTime.month(.abbreviated)).uppercased())\n\(date.formatted(.dateTime.year()))")
                            .font(.system(size: 9, weight: .black)).tracking(0.6).multilineTextAlignment(.center)
                            .frame(width: 58, height: 58)
                            .overlay(Circle().strokeBorder(theme.onHighlight, lineWidth: 2.5))
                            .rotationEffect(.degrees(-14))
                    }
                    .frame(maxHeight: .infinity)
                }
                .foregroundStyle(theme.onHighlight)
                .padding(.horizontal, 22)
            }
            .padding(.horizontal, side).padding(.vertical, top)
            Capsule().fill(theme.brand).frame(width: 8, height: 64).offset(y: -h / 2 + 26)
            mark(.white.opacity(0.6)).offset(x: w / 2 - side - 30, y: h / 2 - 13)
        }
    }
}

// MARK: - Pieces

/// The book's cover at 2:3, or a stand-in in the theme's colours when there is none.
struct CardCover: View {
    let image: UIImage?
    let title: String
    let theme: AppTheme
    let width: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [theme.brand, theme.brandText], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: width * 0.06) {
                        Rectangle().fill(theme.highlight).frame(width: width * 0.3, height: max(2, width * 0.03))
                        Text(title).font(.system(size: max(5, width * 0.13), weight: .bold, design: .serif))
                            .foregroundStyle(theme.onBrand).minimumScaleFactor(0.4)
                    }
                    .padding(width * 0.1)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: max(2, width * 0.035), style: .continuous))
    }
}

/// A star burst with the given number of points.
struct Burst: Shape {
    var points: Int
    var inner: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<(points * 2) {
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let rad = i.isMultiple(of: 2) ? r : r * inner
            let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct Squiggle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY * 0.8))
        p.addCurve(to: CGPoint(x: r.width * 0.45, y: r.midY),
                   control1: CGPoint(x: r.width * 0.15, y: -r.height * 0.4), control2: CGPoint(x: r.width * 0.3, y: r.height * 1.3))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.height * 0.15),
                   control1: CGPoint(x: r.width * 0.6, y: -r.height * 0.3), control2: CGPoint(x: r.width * 0.8, y: r.height * 1.2))
        return p
    }
}

/// A hand-drawn arrow pointing up and to the left.
struct NoteArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + 2, y: r.minY + 2), control: CGPoint(x: r.width * 0.35, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY + 2)); p.addLine(to: CGPoint(x: r.minX + 4, y: r.minY + 12))
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY + 2)); p.addLine(to: CGPoint(x: r.minX + 12, y: r.minY + 4))
        return p
    }
}

struct DashedRule: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

// MARK: - Sheet

/// Preview a note as a card, pick a style, shape and colours, then share or save it.
struct QuoteCardSheet: View {
    let note: BookNote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var currentTheme
    @State private var shape: QuoteCard.Shape = .portrait
    @State private var themeID = ""
    @AppStorage("cardStyle") private var styleRaw = CardStyle.poster.rawValue
    @State private var image: UIImage?

    private var cardTheme: AppTheme { AppTheme.named(themeID.isEmpty ? currentTheme.id : themeID) }
    private var style: CardStyle { CardStyle(rawValue: styleRaw) ?? .poster }
    private var cover: UIImage? { note.book?.coverData.flatMap(UIImage.init(data:)) }

    private func card(_ style: CardStyle, _ shape: QuoteCard.Shape) -> QuoteCard {
        QuoteCard(text: note.text, isQuote: note.kind == .quote, title: note.book?.title ?? "",
                  author: note.book?.author ?? "", page: note.page, theme: cardTheme, shape: shape,
                  style: style, cover: cover, date: note.createdAt)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                                .accessibilityLabel("Card preview")
                        } else {
                            ProgressView().frame(height: 300)
                        }
                    }
                    .frame(maxHeight: shape == .story ? 480 : 380)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CardStyle.allCases) { s in
                                Button { styleRaw = s.rawValue } label: {
                                    VStack(spacing: 5) {
                                        card(s, .portrait)
                                            .scaleEffect(0.22)
                                            .frame(width: 360 * 0.22, height: 450 * 0.22)
                                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(s == style ? Color.primary : Color.clear, lineWidth: 2.5))
                                        Text(s.rawValue).font(.caption2.weight(s == style ? .bold : .regular))
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(s.rawValue) style")
                                .accessibilityIdentifier("style-\(s.rawValue)")
                            }
                        }
                        .padding(.horizontal, 2).padding(.vertical, 2)
                    }

                    Picker("Shape", selection: $shape) {
                        ForEach(QuoteCard.Shape.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AppTheme.all) { t in
                                Button { themeID = t.id } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle().fill(t.board)
                                            Circle().fill(t.brand).frame(width: 18, height: 18).offset(x: -6, y: -4)
                                            Circle().fill(t.highlight).frame(width: 12, height: 12).offset(x: 8, y: 6)
                                        }
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().strokeBorder(t.id == cardTheme.id ? Color.primary : .clear, lineWidth: 2.5))
                                        Text(t.name).font(.caption2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(t.name) colours")
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    if let image {
                        ShareLink(item: Image(uiImage: image),
                                  preview: SharePreview(note.book?.title ?? "Quote", image: Image(uiImage: image))) {
                            Label("Share or save", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PillButton(kind: .brand, big: true))
                        .accessibilityIdentifier("cardShare")
                    }
                    Text("Share to Instagram, Messages or WhatsApp, or choose Save Image to keep it in Photos.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .navigationTitle(note.kind == .quote ? "Quote card" : "Note card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if themeID.isEmpty { themeID = currentTheme.id }; render() }
            .onChange(of: shape) { _, _ in render() }
            .onChange(of: themeID) { _, _ in render() }
            .onChange(of: styleRaw) { _, _ in render() }
        }
    }

    @MainActor private func render() {
        let renderer = ImageRenderer(content: card(style, shape))
        renderer.scale = 3
        image = renderer.uiImage
    }
}
