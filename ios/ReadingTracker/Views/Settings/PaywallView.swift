import SwiftUI

private let features: [(String, String)] = [
    ("timer", "Lock-screen timer"),
    ("cloud.rain", "Focus sounds"),
    ("quote.opening", "Quotes and cards"),
    ("sparkles", "Monthly recap"),
    ("headphones", "Audiobooks"),
    ("books.vertical", "Goodreads import"),
    ("icloud", "iCloud sync"),
    ("square.grid.2x2", "Widgets and themes"),
]

/// Shown when the trial has ended (or from "Unlock"): one payment, no subscription.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaywallHero(badge: "ONE\nPAYMENT").padding(.top, 34)
                Text(headline).font(.system(.largeTitle, design: .rounded, weight: .black))
                Text("One payment unlocks everything, for good. No subscription, no ads, no tracking.")
                    .foregroundStyle(.secondary)
                FeatureList()
                if store.access == .noTrial {
                    Button {
                        Task { await store.startTrial(); if store.access.canEdit { dismiss() } }
                    } label: {
                        Text(store.busy ? "Starting…" : "Start my 3-day free trial")
                    }
                    .buttonStyle(PillButton(kind: .highlight, big: true))
                    .disabled(store.busy)
                    .accessibilityIdentifier("paywallStartTrial")
                }
                Button {
                    Task { await store.unlock(); if store.access == .unlocked { dismiss() } }
                } label: {
                    Text(store.busy ? "Working…" : "Unlock forever" + (store.unlockPrice.isEmpty ? "" : " · \(store.unlockPrice)"))
                }
                .buttonStyle(PillButton(kind: .brand, big: true))
                .disabled(store.busy || store.access == .unlocked)
                .accessibilityIdentifier("buyUnlock")
                Text("One payment · no subscription · yours forever")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Button("Restore purchase") { Task { await store.restore(); if store.access == .unlocked { dismiss() } } }
                    .frame(maxWidth: .infinity)
                    .disabled(store.busy)
                if store.access == .expired {
                    Text("Not ready yet? You can still look through everything you've logged and save a backup from Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Link("Privacy", destination: Links.privacy)
                    Spacer()
                    Link("Help", destination: Links.support)
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary).glassCircle() }
                .padding(16)
                .accessibilityLabel("Close")
        }
        .purchaseAlert()
    }

    private var headline: String {
        switch store.access {
        case .expired: return "Your free trial has ended"
        case .unlocked: return "You're all set"
        default: return "Keep your reading going"
        }
    }
}

/// What you get, as a grid of small tiles.
struct FeatureList: View {
    @Environment(\.theme) private var theme
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(features, id: \.1) { feature in
                HStack(spacing: 10) {
                    Image(systemName: feature.0).font(.subheadline.weight(.bold)).foregroundStyle(theme.onBrand)
                        .frame(width: 32, height: 32).background(theme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(feature.1).font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The picture at the top of the welcome and unlock screens: a fan of books on a block of colour, with a sticker.
struct PaywallHero: View {
    let badge: String
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(theme.brand)
            Circle().fill(theme.highlight).frame(width: 220, height: 220).offset(x: -150, y: 90)
            Burst(points: 4, inner: 0.3).fill(theme.onBrand).frame(width: 26, height: 26).offset(x: -120, y: -62)
            HStack(spacing: -22) {
                book("Jane Eyre", tilt: -10).offset(y: 10)
                book("Pride and Prejudice", tilt: 0).zIndex(1)
                book("Emma", tilt: 10).offset(y: 10)
            }
            .offset(x: -6, y: 8)
            ZStack {
                Burst(points: 10, inner: 0.78).fill(theme.highlight)
                Text(badge).font(.system(size: 12, weight: .black)).multilineTextAlignment(.center)
                    .foregroundStyle(theme.onHighlight).padding(10)
            }
            .frame(width: 86, height: 86)
            .rotationEffect(.degrees(12))
            .offset(x: 112, y: -40)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityHidden(true)
    }

    private func book(_ title: String, tilt: Double) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0x111113), Color(hex: 0x2C2C33)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(theme.highlight).frame(width: 26, height: 3)
                Text(title).font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(.white)
            }
            .padding(10)
        }
        .frame(width: 84, height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 5)
        .rotationEffect(.degrees(tilt))
    }
}

/// First launch: start the 3-day free trial (a free in-app item, so the trial is tied to the Apple ID).
struct WelcomeView: View {
    /// Closes the welcome screen into read-only mode, so a failed or skipped trial never locks anyone out.
    var onLookAround: () -> Void = {}
    @Environment(Store.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PaywallHero(badge: "3 DAYS\nFREE").padding(.top, 8)
                Text("Track every page you read").font(.system(.largeTitle, design: .rounded, weight: .black))
                Text("Time your reading, keep your favourite quotes, and watch your streak grow. Books and audiobooks.")
                    .foregroundStyle(.secondary)
                FeatureList()
                Button {
                    Task { await store.startTrial() }
                } label: {
                    Text(store.busy ? "Starting…" : "Start my 3-day free trial")
                }
                .buttonStyle(PillButton(kind: .brand, big: true))
                .disabled(store.busy)
                .accessibilityIdentifier("startTrial")
                Text("Free for 3 days, with everything included. After that, unlock it forever with one payment\(store.unlockPrice.isEmpty ? "" : " of \(store.unlockPrice)"). No subscription, and nothing is charged automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Look around first", action: onLookAround)
                    .buttonStyle(PillButton(kind: .outline, big: true))
                    .accessibilityIdentifier("lookAround")
                Button("Already bought it? Restore") { Task { await store.restore() } }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .disabled(store.busy)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
        .purchaseAlert()
    }
}

extension View {
    /// Shows purchase messages. In builds run from Xcode, a failed purchase also offers "Unlock for testing".
    func purchaseAlert() -> some View { modifier(PurchaseAlert()) }
}

private struct PurchaseAlert: ViewModifier {
    @Environment(Store.self) private var store

    func body(content: Content) -> some View {
        content.alert(store.message ?? "", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            #if DEBUG
            if store.purchaseFailed {
                Button("Unlock for testing") { store.unlockForTesting() }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            #if DEBUG
            if store.purchaseFailed {
                Text("Testing build only: you can unlock everything to keep testing. This option never appears in the App Store version.")
            }
            #endif
        }
    }
}
