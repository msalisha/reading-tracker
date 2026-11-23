import SwiftUI

/// Decorative, book-themed backgrounds for shareable cards, drawn in the colour scheme's own colours.
/// Everything is drawn in code (no images), so they look crisp at any size and in every theme.
enum CardBackground: String, CaseIterable, Identifiable {
    case glow = "Glow"
    case shelf = "Bookshelf"
    case paper = "Paper"
    case openBook = "Open book"
    case confetti = "Confetti"
    case plain = "Plain"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .glow: return "sparkles"
        case .shelf: return "books.vertical"
        case .paper: return "note.text"
        case .openBook: return "book"
        case .confetti: return "party.popper"
        case .plain: return "square"
        }
    }
}

struct CardBackdrop: View {
    let style: CardBackground
    let theme: AppTheme

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.board))
            switch style {
            case .plain: break
            case .glow: drawGlow(&ctx, size)
            case .shelf: drawGlow(&ctx, size, soft: true); drawShelf(&ctx, size)
            case .paper: drawPaper(&ctx, size)
            case .openBook: drawGlow(&ctx, size, soft: true); drawOpenBook(&ctx, size)
            case .confetti: drawConfetti(&ctx, size)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: styles

    private func drawGlow(_ ctx: inout GraphicsContext, _ s: CGSize, soft: Bool = false) {
        let w = s.width, h = s.height
        let k = soft ? 0.5 : 1.0
        blob(&ctx, center: CGPoint(x: w * 0.92, y: h * 0.06), radius: w * 0.85, color: theme.brand, opacity: 0.55 * k)
        blob(&ctx, center: CGPoint(x: w * 0.02, y: h * 0.96), radius: w * 0.8, color: theme.highlight, opacity: 0.32 * k)
        blob(&ctx, center: CGPoint(x: w * 0.15, y: h * 0.35), radius: w * 0.45, color: theme.brandText, opacity: 0.16 * k)
    }

    private func blob(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                                       center: center, startRadius: 0, endRadius: radius))
    }

    /// A row of book spines standing on a shelf along the bottom, leaving the right-hand corner for the footer.
    private func drawShelf(_ ctx: inout GraphicsContext, _ s: CGSize) {
        var rng = Seeded(7)
        let w = s.width, h = s.height
        let base = h * 0.975
        let colors = [theme.brand, theme.highlight, theme.boardMuted, theme.brandText]
        var x = w * 0.04
        var i = 0
        while x < w * 0.66 {
            let bw = 10 + rng.next() * 14
            let bh = h * (0.08 + rng.next() * 0.1)
            let lean: CGFloat = i == 5 ? 0.18 : 0
            var spine = Path(roundedRect: CGRect(x: 0, y: -bh, width: bw, height: bh), cornerRadius: 2.5)
            spine = spine.applying(CGAffineTransform(rotationAngle: lean))
            spine = spine.applying(CGAffineTransform(translationX: x + (lean > 0 ? bh * 0.1 : 0), y: base))
            let c = colors[i % colors.count]
            ctx.fill(spine, with: .color(c.opacity(0.42)))
            // a band near the top of each spine, like a title label
            let band = CGRect(x: x + 2, y: base - bh * 0.78, width: bw - 4, height: 3)
            if lean == 0 { ctx.fill(Path(band), with: .color(theme.board.opacity(0.35))) }
            x += bw + 2 + (lean > 0 ? bh * 0.2 : 0)
            i += 1
        }
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: base, width: w, height: h - base), cornerRadius: 0),
                 with: .color(theme.boardMuted.opacity(0.4)))
    }

    /// Lined notebook paper: faint rules, a margin line, and a folded corner.
    private func drawPaper(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height
        let gap: CGFloat = max(22, h / 26)
        var y = h * 0.14
        while y < h - 10 {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(line, with: .color(theme.boardMuted.opacity(0.16)), lineWidth: 1)
            y += gap
        }
        var margin = Path()
        margin.move(to: CGPoint(x: w * 0.06, y: 0))
        margin.addLine(to: CGPoint(x: w * 0.06, y: h))
        ctx.stroke(margin, with: .color(theme.brand.opacity(0.45)), lineWidth: 1.5)
        // binder holes
        for f: CGFloat in [0.2, 0.5, 0.8] {
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.018, y: h * f - 4, width: 8, height: 8)), with: .color(theme.boardMuted.opacity(0.25)))
        }
        // dog-eared corner
        let d = w * 0.13
        var fold = Path()
        fold.move(to: CGPoint(x: w - d, y: 0))
        fold.addLine(to: CGPoint(x: w, y: d))
        fold.addLine(to: CGPoint(x: w - d, y: d))
        fold.closeSubpath()
        ctx.fill(fold, with: .color(theme.highlight.opacity(0.55)))
        var corner = Path()
        corner.move(to: CGPoint(x: w - d, y: 0))
        corner.addLine(to: CGPoint(x: w, y: 0))
        corner.addLine(to: CGPoint(x: w, y: d))
        corner.closeSubpath()
        ctx.fill(corner, with: .color(Color.black.opacity(0.35)))
    }

    /// A large, faint open book with lines of "text" on each page.
    private func drawOpenBook(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height
        let cx = w / 2
        let top = h * 0.5, bottom = h * 0.9
        let pw = w * 0.44
        for side: CGFloat in [-1, 1] {
            var page = Path()
            page.move(to: CGPoint(x: cx, y: top + 10))
            page.addQuadCurve(to: CGPoint(x: cx + side * pw, y: top), control: CGPoint(x: cx + side * pw * 0.5, y: top - 18))
            page.addLine(to: CGPoint(x: cx + side * pw, y: bottom - 8))
            page.addQuadCurve(to: CGPoint(x: cx, y: bottom), control: CGPoint(x: cx + side * pw * 0.5, y: bottom - 22))
            page.closeSubpath()
            ctx.fill(page, with: .color(theme.boardText.opacity(0.05)))
            ctx.stroke(page, with: .color(theme.brand.opacity(0.45)), lineWidth: 2)
            // text lines
            var y = top + 22
            while y < bottom - 26 {
                var line = Path()
                let inset = pw * 0.14
                line.move(to: CGPoint(x: cx + side * inset, y: y + 6))
                line.addLine(to: CGPoint(x: cx + side * (pw - inset), y: y))
                ctx.stroke(line, with: .color(theme.boardMuted.opacity(0.18)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                y += 13
            }
        }
        // spine and a ribbon bookmark
        var spine = Path()
        spine.move(to: CGPoint(x: cx, y: top + 10))
        spine.addLine(to: CGPoint(x: cx, y: bottom))
        ctx.stroke(spine, with: .color(theme.brand.opacity(0.6)), lineWidth: 2)
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: cx + 8, y: top + 8))
        ribbon.addLine(to: CGPoint(x: cx + 8, y: bottom + 26))
        ribbon.addLine(to: CGPoint(x: cx + 13, y: bottom + 20))
        ribbon.addLine(to: CGPoint(x: cx + 18, y: bottom + 26))
        ribbon.addLine(to: CGPoint(x: cx + 18, y: top + 6))
        ribbon.closeSubpath()
        ctx.fill(ribbon, with: .color(theme.highlight.opacity(0.7)))
    }

    /// Celebration confetti: little dots, strips and stars around the edges, keeping the middle calm.
    private func drawConfetti(_ ctx: inout GraphicsContext, _ s: CGSize) {
        var rng = Seeded(42)
        let w = s.width, h = s.height
        let colors = [theme.brand, theme.highlight, theme.boardText, theme.brandText]
        for i in 0..<70 {
            var x = rng.next() * w, y = rng.next() * h
            // push pieces out of the central text area
            if x > w * 0.12 && x < w * 0.88 && y > h * 0.2 && y < h * 0.8 {
                if rng.next() < 0.5 { x = rng.next() < 0.5 ? rng.next() * w * 0.12 : w * 0.88 + rng.next() * w * 0.12 }
                else { y = rng.next() < 0.5 ? rng.next() * h * 0.2 : h * 0.8 + rng.next() * h * 0.2 }
            }
            let c = colors[i % colors.count].opacity(0.35 + rng.next() * 0.4)
            let size = 4 + rng.next() * 7
            var piece: Path
            switch i % 3 {
            case 0: piece = Path(ellipseIn: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            case 1: piece = Path(roundedRect: CGRect(x: -size, y: -size * 0.3, width: size * 2, height: size * 0.6), cornerRadius: 1.5)
            default: piece = star(size)
            }
            piece = piece.applying(CGAffineTransform(rotationAngle: rng.next() * .pi))
                .applying(CGAffineTransform(translationX: x, y: y))
            ctx.fill(piece, with: .color(c))
        }
    }

    private func star(_ r: CGFloat) -> Path {
        var p = Path()
        for k in 0..<10 {
            let a = CGFloat(k) * .pi / 5 - .pi / 2
            let rr = k % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Small repeatable random numbers, so a background looks the same every time it's drawn.
struct Seeded {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493 }
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(state >> 11) / Double(1 << 53))
    }
}
