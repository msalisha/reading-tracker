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
            .contentTransition(.numericText())
            .animation(.snappy, value: text)
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

/// A small ring with the percentage inside.
struct ProgressRing: View {
    let fraction: Double
    var color: Color
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: fraction)
            Text("\(Int((fraction * 100).rounded()))%").font(.system(size: size * 0.27, weight: .black, design: .rounded)).monospacedDigit()
        }
        .frame(width: size, height: size)
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

/// A small "Audiobook" tag.
struct AudioBadge: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Label("Audiobook", systemImage: "headphones")
            .font(.caption2.weight(.bold))
            .foregroundStyle(theme.brandText)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(theme.brandText.opacity(0.12), in: Capsule())
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
                FittedCover(image: img)
            } else {
                // a stand-in that still looks like a book: a spine shadow, a coloured band and the title
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [theme.brand, theme.brandText], startPoint: .topLeading, endPoint: .bottomTrailing)
                    LinearGradient(colors: [Color.black.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(3, width * 0.09))
                    if width >= 64 {
                        VStack(alignment: .leading, spacing: width * 0.06) {
                            Rectangle().fill(theme.highlight).frame(width: width * 0.3, height: max(2, width * 0.03))
                            Text(title).font(.system(size: width * 0.13, weight: .bold, design: .serif))
                                .foregroundStyle(theme.onBrand).minimumScaleFactor(0.5).multilineTextAlignment(.leading)
                        }
                        .padding(.leading, width * 0.16).padding(.trailing, width * 0.08).padding(.top, width * 0.14)
                    } else {
                        Text(title.prefix(1).uppercased())
                            .font(.system(size: width * 0.42, weight: .bold, design: .serif))
                            .foregroundStyle(theme.onBrand)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: width * 0.06, y: width * 0.04)
        .accessibilityHidden(true)
    }
}

/// Shows the whole cover in a book-shaped (2:3) box, never cropping it. If the picture isn't exactly that shape,
/// the spare space is filled with a soft blurred copy of the picture, so it still looks like a cover.
struct FittedCover: View {
    let image: UIImage

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().scaledToFill().blur(radius: 14).opacity(0.75)
            Color.black.opacity(0.1)
            Image(uiImage: image).resizable().scaledToFit()
        }
    }
}

/// Rounded pill buttons in theme colours.
struct PillButton: ButtonStyle {
    enum Kind { case solid, brand, highlight, outline, danger }
    var kind: Kind = .solid
    var big = false
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(big ? .headline : .subheadline.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, big ? 16 : 11)
            .padding(.horizontal, 14)
            .foregroundStyle(fg)
        if kind == .outline {
            label
                .glassCapsule(outline: Color.primary.opacity(0.5))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
        } else {
            label
                .background(bg, in: Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
        }
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

/// Hours and minutes boxes for an audiobook position or length. Reads and writes a total number of minutes as
/// text, the same way the page boxes hold a page number.
struct DurationInput: View {
    @Binding var minutesText: String
    var identifier: String
    var focused: FocusState<Bool>.Binding? = nil
    var boxed = false
    @State private var hours = ""
    @State private var mins = ""

    var body: some View {
        HStack(spacing: 4) {
            box(TextField("0", text: $hours), id: identifier + "Hours", focus: true)
            Text("h").font(.subheadline.weight(.semibold))
            box(TextField("00", text: $mins), id: identifier + "Minutes", focus: false)
            Text("m").font(.subheadline.weight(.semibold))
        }
        .onAppear(perform: pull)
        .onChange(of: minutesText) { _, _ in if total != Int(trimming: minutesText) { pull() } }
        .onChange(of: hours) { _, _ in push() }
        .onChange(of: mins) { _, _ in push() }
    }

    private var total: Int? {
        hours.isEmpty && mins.isEmpty ? nil : (Int(trimming: hours) ?? 0) * 60 + (Int(trimming: mins) ?? 0)
    }

    private func pull() {
        if let t = Int(trimming: minutesText) { hours = "\(t / 60)"; mins = String(format: "%02d", t % 60) } else { hours = ""; mins = "" }
    }

    private func push() {
        let new = total.map(String.init) ?? ""
        if new != minutesText { minutesText = new }
    }

    @ViewBuilder private func box(_ field: TextField<Text>, id: String, focus: Bool) -> some View {
        let f = field.keyboardType(.numberPad).multilineTextAlignment(.center).accessibilityIdentifier(id)
        Group {
            if focus, let focused { f.focused(focused) } else { f }
        }
        .font(boxed ? .title3.weight(.bold) : .body)
        .foregroundStyle(boxed ? Color(hex: 0x111113) : Color.primary)
        .padding(.vertical, boxed ? 10 : 4)
        .frame(width: boxed ? 52 : 44)
        .background(boxed ? Color.white : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: boxed ? 12 : 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0x111113), lineWidth: boxed ? 1.5 : 0))
    }
}

/// A labelled page-number box (or hours and minutes, for an audiobook).
struct PageField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var identifier: String
    var focused: FocusState<Bool>.Binding
    var isAudio = false

    var body: some View {
        HStack {
            Text(label).font(.subheadline.weight(.bold))
            Spacer()
            if isAudio {
                DurationInput(minutesText: $text, identifier: identifier, focused: focused, boxed: true)
            } else {
                pageBox
            }
        }
    }

    private var pageBox: some View {
        Group {
            TextField(placeholder, text: $text)
                .focused(focused)
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
