import SwiftUI

private let features: [(String, String)] = [
    ("timer", "Reading timer on your lock screen"),
    ("barcode.viewfinder", "Scan a book's barcode to add it"),
    ("quote.opening", "Notes, quotes and star ratings"),
    ("chart.bar.fill", "Streaks, pace and monthly stats"),
    ("square.grid.2x2", "Home-screen widgets"),
    ("paintpalette", "Six colour schemes"),
]

/// Shown when the trial has ended (or from "Unlock"): one payment, no subscription.
struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(headline).font(.system(.largeTitle, design: .rounded, weight: .black))
                Text("One payment unlocks everything, for good. No subscription, no ads, and your reading stays on your phone.")
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

struct FeatureList: View {
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.1) { feature in
                Label { Text(feature.1) } icon: { Image(systemName: feature.0).foregroundStyle(theme.brandText).frame(width: 28) }
            }
        }
        .font(.body.weight(.medium))
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
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 6) {
                    Capsule().fill(theme.brand).frame(width: 56, height: 8)
                    Capsule().fill(theme.highlight).frame(width: 36, height: 8)
                    Capsule().fill(theme.brandText).frame(width: 20, height: 8)
                }
                .padding(.top, 40)
                Text("Track every page you read").font(.system(.largeTitle, design: .rounded, weight: .black))
                Text("Time your reading, log your pages, keep quotes and thoughts, and watch your streak grow.")
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
