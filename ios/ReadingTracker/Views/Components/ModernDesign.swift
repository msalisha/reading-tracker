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
