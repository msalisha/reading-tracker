import SwiftUI
import UIKit

/// The chunky rounded numbers used for scores.
struct BigNumber: View {
    let text: String
    var color: Color? = nil
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color ?? .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Small uppercase label.
struct Eyebrow: View {
    let text: String
    var color: Color? = nil

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color ?? .secondary)
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(.title2, design: .rounded, weight: .heavy))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.top, 6)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var color: Color
    var track: Color = Color(.systemGray5)
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Little filled line of the page reached over time.
struct Sparkline: View {
    let points: [(Date, Int)]
    let total: Int
    var color: Color

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2, let t0 = points.first?.0.timeIntervalSince1970, let t1 = points.last?.0.timeIntervalSince1970 {
                let span = max(1, t1 - t0)
                let w = geo.size.width, h = geo.size.height
                let pts = points.map { CGPoint(x: CGFloat(($0.0.timeIntervalSince1970 - t0) / span) * w,
                                               y: h - CGFloat(Double($0.1) / Double(max(1, total))) * h) }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                        p.closeSubpath()
                    }.fill(color.opacity(0.14))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 1))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 1))
                }.stroke(Color(.systemGray4), lineWidth: 2)
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

/// Optional half-star rating. Tap or drag to set; tap the same value again to clear.
struct StarRating: View {
    @Binding var rating: Double?
    var size: CGFloat = 30
    var color: Color = .orange
    var editable = true

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(for: Double(i)))
                    .font(.system(size: size))
                    .foregroundStyle(color)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in if editable { set(at: g.location.x) } })
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { "\($0.formatted()) out of 5 stars" } ?? "Not rated")
        .accessibilityAdjustableAction { dir in
            guard editable else { return }
            let r = rating ?? 0
            let next = dir == .increment ? min(5, r + 0.5) : max(0, r - 0.5)
            rating = next == 0 ? nil : next
        }
    }

    private var starWidth: CGFloat { size * 1.15 }

    private func symbol(for i: Double) -> String {
        let r = rating ?? 0
        if r >= i { return "star.fill" }
        if r >= i - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    private func set(at x: CGFloat) {
        let raw = (Double(x / starWidth) * 2).rounded(.up) / 2
        let value = min(5, max(0.5, raw))
        rating = rating == value ? nil : value
        Haptics.tap()
    }
}

struct CoverView: View {
    let data: Data?
    let title: String
    var width: CGFloat = 54
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.brand
                    Text(title.prefix(1).uppercased())
                        .font(.system(size: width * 0.45, weight: .black, design: .rounded))
                        .foregroundStyle(theme.onBrand)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.1, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Rounded pill buttons in theme colours.
struct PillButton: ButtonStyle {
    enum Kind { case solid, brand, highlight, outline, danger }
    var kind: Kind = .solid
    var big = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(big ? .headline : .subheadline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, big ? 16 : 11)
            .padding(.horizontal, 14)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .outline ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }

    private var bg: Color {
        switch kind {
        case .solid: return Color.primary
        case .brand: return theme.brand
        case .highlight: return theme.highlight
        case .outline: return .clear
        case .danger: return Color(hex: 0x8A0F4D)
        }
    }

    private var fg: Color {
        switch kind {
        case .solid: return Color(.systemBackground)
        case .brand: return theme.onBrand
        case .highlight: return theme.onHighlight
        case .outline: return .primary
        case .danger: return .white
        }
    }
}

extension View {
    func card(_ color: Color, radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Number-pad text field styling for page numbers.
    func numericField() -> some View {
        self.keyboardType(.numberPad).multilineTextAlignment(.center).font(.title3.weight(.bold))
    }
}

/// A labelled page-number box.
struct PageField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var identifier: String

    var body: some View {
        HStack {
            Text(label).font(.subheadline.weight(.bold))
            Spacer()
            TextField(placeholder, text: $text)
                .numericField()
                .foregroundStyle(Color(hex: 0x111113))
                .padding(.vertical, 10)
                .frame(width: 120)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0x111113), lineWidth: 1.5))
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }
}

extension Int {
    init?(trimming s: String) { self.init(s.trimmingCharacters(in: .whitespaces)) }
}
