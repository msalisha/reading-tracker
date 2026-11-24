import SwiftUI

// iOS 26 "Liquid Glass" touches. Built with Xcode 26 or later, standard bars, sheets and menus pick up the
// new look automatically; these add it to Pageturner's own pieces. Phones on iOS 17–18 keep the classic look.

extension View {
    /// The tab bar shrinks out of the way while you scroll (iOS 26+).
    @ViewBuilder func modernTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A see-through glass capsule behind outline buttons (iOS 26+); a plain outline before that.
    @ViewBuilder func glassCapsule(outline: Color) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.overlay(Capsule().strokeBorder(outline, lineWidth: 1.5))
        }
        #else
        self.overlay(Capsule().strokeBorder(outline, lineWidth: 1.5))
        #endif
    }

    /// Floating controls (like a close button) sit on glass on iOS 26+.
    @ViewBuilder func glassCircle() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.padding(6).glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// A short burst of confetti in the theme's colours, for finishing a book.
struct ConfettiBurst: View {
    let theme: AppTheme
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSince(start)
                    guard t < 3.2 else { return }
                    var rng = Seeded(42)
                    let colors = [theme.brand, theme.highlight, theme.brandText, Color.yellow, Color.white]
                    for i in 0..<110 {
                        let angle = Double(rng.next()) * .pi - .pi          // upwards fan
                        let speed = 260 + Double(rng.next()) * 520
                        let spin = Double(rng.next()) * 8 - 4
                        let w = 6 + rng.next() * 7, h = 9 + rng.next() * 9
                        let x = Double(size.width) / 2 + cos(angle) * speed * t
                        let y = Double(size.height) * 0.42 + sin(angle) * speed * t + 520 * t * t
                        var piece = ctx
                        piece.opacity = max(0, 1 - t / 3.2)
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(spin * t))
                        piece.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 2),
                                   with: .color(colors[i % colors.count]))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
