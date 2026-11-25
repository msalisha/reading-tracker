import Foundation
import Observation
import StoreKit

/// What the reader can do right now.
enum Access: Equatable {
    case loading
    /// Hasn't started the free trial yet.
    case noTrial
    case trial(endsAt: Date)
    /// Trial over and not bought: everything is visible, nothing new can be added.
    case expired
    case unlocked

    var canEdit: Bool {
        switch self {
        case .trial, .unlocked, .loading: return true
        case .noTrial, .expired: return false
        }
    }
}

/// The trial rules, kept apart from StoreKit so they can be tested with any clock.
enum AccessRules {
    static let trialLength: TimeInterval = 3 * 24 * 60 * 60

    static func access(trialStart: Date?, unlocked: Bool, now: Date) -> Access {
        if unlocked { return .unlocked }
        guard let start = trialStart else { return .noTrial }
        let end = start.addingTimeInterval(trialLength)
        return now.seconds < end.seconds ? .trial(endsAt: end) : .expired
    }

    /// "3 days left", "1 day left", "5 hours left".
    static func timeLeft(until end: Date, now: Date) -> String {
        let secs = max(0, end.timeIntervalSince(now))
        let days = Int((secs / 86_400).rounded(.up))
        if secs > 86_400 { return "\(days) days left" }
        let hours = max(1, Int((secs / 3600).rounded(.up)))
        return hours >= 24 ? "1 day left" : "\(hours) \(hours == 1 ? "hour" : "hours") left"
    }
}

/// The App Store side: a free "3-Day Free Trial" item and a paid "Unlock forever" item,
/// both non-consumable (Apple's approved pattern for a free trial before a one-off purchase).
@MainActor
@Observable
final class Store {
    static let trialID = "trial.3day"
    static let unlockID = "unlock.lifetime"

    private(set) var trialStart: Date?
    private(set) var unlocked = false
    private(set) var loaded = false
    private(set) var products: [String: Product] = [:]
    var busy = false
    var message: String?
    /// True after a purchase attempt fails, so debug builds can offer a testing unlock.
    var purchaseFailed = false
    /// Bumped when the app comes to the front, so a trial that ran out while away shows as ended.
    var now = Date()

    @ObservationIgnored private var updates: Task<Void, Never>?
    private var forced: Access?

    var access: Access {
        if let forced { return forced }
        guard loaded else { return .loading }
        return AccessRules.access(trialStart: trialStart, unlocked: unlocked, now: now)
    }

    var unlockPrice: String { products[Self.unlockID]?.displayPrice ?? "" }

    init(forced: Access? = nil) {
        self.forced = forced
        guard forced == nil else { loaded = true; return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh(); await loadProducts() }
    }

    func refresh() async {
        var start: Date?, owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == Self.unlockID { owned = true }
            if t.productID == Self.trialID {
                let first = t.originalPurchaseDate.seconds < t.purchaseDate.seconds ? t.originalPurchaseDate : t.purchaseDate
                if start == nil || first.seconds < start!.seconds { start = first }
            }
        }
        trialStart = start
        unlocked = owned
        now = Date()
        loaded = true
    }

    /// Why the last attempt to load the purchases failed, if it did (nil when the App Store simply returned fewer).
    @ObservationIgnored private var loadError: Error?

    func loadProducts() async {
        do {
            let list = try await Product.products(for: [Self.trialID, Self.unlockID])
            loadError = nil
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            loadError = error
        }
    }

    /// Called when the app comes to the front: picks the purchases up as soon as the App Store offers them.
    func loadProductsIfMissing() async {
        if products.count < 2 { await loadProducts() }
    }

    func startTrial() async { await buy(Self.trialID) }

    #if DEBUG
    /// Only in builds run from Xcode: lets you use the app when test purchases aren't working.
    func unlockForTesting() {
        forced = .unlocked
        purchaseFailed = false
        message = nil
    }
    #endif
    func unlock() async { await buy(Self.unlockID) }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = access == .unlocked ? "Purchase restored. Thank you!" : "No purchase found for this Apple ID."
        } catch {
            message = "Couldn't reach the App Store. Try again in a moment."
        }
    }

    private func buy(_ id: String) async {
        if products[id] == nil { await loadProducts() }
        if products[id] == nil {   // one more try before saying anything
            try? await Task.sleep(for: .seconds(1))
            await loadProducts()
        }
        guard let product = products[id] else {
            message = StoreErrors.unavailable(found: products.count, of: 2, error: loadError)
            return
        }
        busy = true
        purchaseFailed = false
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish() }
                await refresh()
            case .pending:
                message = "Waiting for approval. It will unlock as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            let text = StoreErrors.message(for: error)
            if !text.isEmpty {
                message = text
                purchaseFailed = true
            }
        }
    }
}

/// Plain-English reasons a purchase failed.
enum StoreErrors {
    /// Why a purchase couldn't even be offered: no connection, the App Store not offering it (yet), or something else.
    static func unavailable(found: Int, of wanted: Int, error: Error?) -> String {
        guard let error else {
            return "The App Store isn't offering this purchase yet (it returned \(found) of \(wanted)). If the app has only just been set up, this can take a few hours. Please try again later."
        }
        if let e = error as? StoreKitError, case .networkError = e { return "Couldn't reach the App Store. Check your connection and try again." }
        if (error as? URLError) != nil { return "Couldn't reach the App Store. Check your connection and try again." }
        return "The App Store couldn't load this purchase: \(error.localizedDescription)"
    }

    static let notAllowed = "In-app purchases are turned off on this iPhone. Turn them on in Settings → Screen Time → Content & Privacy Restrictions → iTunes & App Store Purchases → In-app Purchases, then try again."
    static let network = "There's no connection to the App Store right now. Check your internet connection and try again. You haven't been charged."
    static let unavailable = "This isn't available in your country's App Store yet. You haven't been charged."

    /// Returns "" when the person simply cancelled.
    static func message(for error: Error) -> String {
        if let e = error as? Product.PurchaseError {
            switch e {
            case .purchaseNotAllowed: return notAllowed
            case .productUnavailable: return unavailable
            default: break
            }
        }
        if let e = error as? StoreKitError {
            switch e {
            case .userCancelled: return ""
            case .networkError: return network
            case .notAvailableInStorefront: return unavailable
            default: break
            }
        }
        return "The purchase didn't go through (\(error.localizedDescription)). You haven't been charged."
    }
}
