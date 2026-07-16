import Foundation
import RevenueCat
import Observation

/// Single source of truth for monetization — now backed by RevenueCat +
/// Virtual Currencies, not raw StoreKit. Views read the credit balance and
/// subscription status from here and never touch the SDK directly.
///
/// Model:
/// - Credits are a RevenueCat **Virtual Currency** (code `CRD`). RevenueCat is
///   the authoritative balance: purchases (consumable packs, subscription
///   renewals) *grant* credits automatically via dashboard product
///   associations. This client only ever *reads* the balance.
/// - Spending is NOT possible from the SDK by design. A spend is a negative
///   adjustment issued by our Vercel backend (which holds the RevenueCat
///   secret key) — see `backend/api/spend.js` and the server-side deduct folded
///   into `backend/api/insight.js`. After a spend we re-read the balance.
///
/// ─────────────────────────────────────────────────────────────────────────
/// CONFIG — replace these placeholders once the RevenueCat dashboard is set up:
///   • `publicAPIKey`      → your RevenueCat *public* SDK key (safe to embed).
///   • `creditCurrencyCode`→ must equal the Virtual Currency code you create.
///   • Product identifiers in `ProductID` must match App Store Connect + the
///     RevenueCat Offering exactly.
///   • The backend needs REVENUECAT_SECRET_KEY + REVENUECAT_PROJECT_ID env vars.
/// ─────────────────────────────────────────────────────────────────────────
@MainActor
@Observable
final class PurchaseManager {
    // MARK: - CONFIG placeholders

    /// RevenueCat public SDK key. Safe to ship in the binary (it can only read
    /// and make purchases, never adjust balances). Replace with the real key.
    static let publicAPIKey = "test_yaBAvZoAxrXPEqVNSzedLwOlNfN"

    /// Virtual Currency code configured in RevenueCat (Product Catalog →
    /// Virtual Currencies). Must match exactly.
    static let creditCurrencyCode = "CRD"

    /// Product identifiers — must match App Store Connect and the RevenueCat
    /// Offering. Packs are consumables; `monthly` is the auto-renewable
    /// subscription that grants +50 CRD on each paid renewal (configured as a
    /// Virtual Currency *associated product* in the dashboard, so no
    /// renewal-listening code is needed here).
    enum ProductID: String, CaseIterable {
        case pack10 = "credits_pack_10"
        case pack50 = "credits_pack_50"
        case monthly = "credits_monthly_50"
    }

    // MARK: - Credit costs (app-side constants; the real gate is RevenueCat)
    // `nonisolated` so pure constants/helpers can be read from non-main-actor
    // contexts (e.g. PaywallView.Context) without a Swift 6 isolation error.

    nonisolated static let analysisCost = 1
    /// Deep analysis: the date-range scan with the long story + photo captions.
    nonisolated static let deepAnalysisCost = 5
    /// Hand-picked Deep Vision: the user-selected ≤30 photo batch.
    nonisolated static let deepVisionCost = 5
    nonisolated static let starterCredits = 3

    /// Cost of one analysis run at the given depth.
    nonisolated static func cost(for depth: AnalysisDepth) -> Int {
        depth == .deep ? deepAnalysisCost : analysisCost
    }

    /// Credits granted per purchase, mirrored client-side purely for paywall
    /// framing ("10 credits = 10 analyses"). The authoritative grant is the
    /// associated-product amount configured in the RevenueCat dashboard — keep
    /// these in sync with it.
    nonisolated static func advertisedCredits(forProductID id: String) -> Int? {
        switch ProductID(rawValue: id) {
        case .pack10: return 10
        case .pack50: return 50
        case .monthly: return 50
        case nil: return nil
        }
    }

    /// Whether a product is the recurring subscription (vs. a one-time pack).
    nonisolated static func isSubscription(productID id: String) -> Bool {
        ProductID(rawValue: id) == .monthly
    }

    // MARK: - Published state

    /// Latest RevenueCat Offering set, for the paywall. `nil` until loaded.
    private(set) var offerings: Offerings?
    /// Authoritative CRD balance, mirrored from RevenueCat.
    private(set) var creditBalance = 0
    /// Whether the monthly credit subscription is active. Drives the
    /// "Subscriber" badge only — it grants no features beyond the credits it
    /// tops up. Independent from the balance.
    private(set) var isSubscribed = false
    /// Whether this customer has ever completed a real purchase (any credit
    /// pack or the subscription) — as opposed to just having a balance from
    /// the free starter grant. Once true, stays true even if the balance
    /// later drops to 0; it gates access to locked analysis modes, not
    /// individual analyses (that's `creditBalance`).
    private(set) var hasUnlockedModes = false
    private(set) var isLoadingOfferings = false
    private(set) var purchaseInFlight = false
    var lastError: String?

    /// Populated after a successful purchase so the UI can show a celebration.
    struct PurchaseResult {
        let creditsAdded: Int
        let newBalance: Int
    }
    var lastPurchaseResult: PurchaseResult?

    /// Stable RevenueCat App User ID for this install. Anonymous by default;
    /// the backend uses it to target the right customer for spends/grants.
    var appUserID: String { Purchases.isConfigured ? Purchases.shared.appUserID : "unconfigured" }

    private var customerInfoTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Call once, before any `Purchases.shared` use (see RoastMyGalleryApp).
    static func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: publicAPIKey)
    }

    init() {
        // React to subscription changes / cross-device updates. Guarded so
        // SwiftUI previews (which never call `configure()`) don't crash.
        guard Purchases.isConfigured else { return }
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                self.updateSubscription(from: info)
                await self.refreshBalance()
            }
        }
    }

    /// One-shot startup: load products, confirm subscription status, read the
    /// balance, and grant first-launch starter credits if this user is new.
    func bootstrap() async {
        guard Purchases.isConfigured else { return }
        primeCachedBalance()
        await loadOfferings()
        await refreshCustomerInfo()
        await ensureStarterGrant()
        await refreshBalance()
    }

    // MARK: - Offerings (paywall)

    func loadOfferings() async {
        guard Purchases.isConfigured else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            lastError = "Couldn't load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Subscription status

    func refreshCustomerInfo() async {
        guard Purchases.isConfigured else { return }
        do {
            updateSubscription(from: try await Purchases.shared.customerInfo())
        } catch {
            // Keep last known status on transient failure.
        }
    }

    private func updateSubscription(from info: CustomerInfo) {
        isSubscribed = !info.entitlements.active.isEmpty
            || info.activeSubscriptions.contains(ProductID.monthly.rawValue)
        // The backend-issued starter grant never appears in StoreKit
        // transaction history, so this only flips true on a real purchase.
        hasUnlockedModes = isSubscribed || !info.nonSubscriptionTransactions.isEmpty
    }

    // MARK: - Balance (Virtual Currency)

    /// Cache-first, no network — call before rendering for an instant balance.
    func primeCachedBalance() {
        guard Purchases.isConfigured,
              let cached = Purchases.shared.cachedVirtualCurrencies else { return }
        creditBalance = cached.all[Self.creditCurrencyCode]?.balance ?? creditBalance
    }

    /// Authoritative fetch from RevenueCat. Falls back to the cached value on
    /// network failure rather than zeroing a real balance.
    func refreshBalance() async {
        guard Purchases.isConfigured else { return }
        do {
            let currencies = try await Purchases.shared.virtualCurrencies()
            creditBalance = currencies.all[Self.creditCurrencyCode]?.balance ?? 0
        } catch {
            primeCachedBalance()
        }
    }

    /// UX-only affordability check. The real gate is RevenueCat rejecting an
    /// over-spend server-side; this just lets us route to the paywall early.
    func canAfford(_ amount: Int) -> Bool { creditBalance >= amount }

    // MARK: - Purchasing

    func purchase(_ package: Package) async {
        guard Purchases.isConfigured else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        lastError = nil
        lastPurchaseResult = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return }
            updateSubscription(from: result.customerInfo)
            // RevenueCat applies the credit grant server-side; drop the stale
            // cache and re-read.
            let balanceBefore = creditBalance
            Purchases.shared.invalidateVirtualCurrenciesCache()
            await refreshBalance()
            let creditsAdded = creditBalance - balanceBefore
            // Fallback: if the delta is zero (race / cache), use the product's
            // advertised amount so the celebration still makes sense.
            let productID = package.storeProduct.productIdentifier
            let displayCredits = creditsAdded > 0
                ? creditsAdded
                : (Self.advertisedCredits(forProductID: productID) ?? creditsAdded)
            lastPurchaseResult = PurchaseResult(
                creditsAdded: displayCredits,
                newBalance: creditBalance
            )
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    enum RestoreResult: Equatable {
        case restoredSubscription
        case noPurchases
        case failed(String)
    }

    /// Restores the *subscription* entitlement. Consumable credit packs cannot
    /// be restored by design — once granted, the credits live in RevenueCat's
    /// balance for this App User ID. (Cross-device continuity requires logging
    /// the user into a stable RevenueCat identity; anonymous IDs can lose a
    /// consumable balance on reinstall. See known limitations.)
    @discardableResult
    func restorePurchases() async -> RestoreResult {
        guard Purchases.isConfigured else { return .failed("Store unavailable.") }
        lastError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            updateSubscription(from: info)
            Purchases.shared.invalidateVirtualCurrenciesCache()
            await refreshBalance()
            return isSubscribed ? .restoredSubscription : .noPurchases
        } catch {
            let message = "Restore failed: \(error.localizedDescription)"
            lastError = message
            return .failed(message)
        }
    }

    // MARK: - Spending & grants (via our backend, which holds the secret key)

    /// Spend credits for an action the *client* orchestrates (e.g. Deep Vision,
    /// which has no dedicated backend endpoint yet). Analysis spend is folded
    /// into `POST /api/insight` server-side instead, so it is NOT routed here.
    ///
    /// Deduct-after-success: only call this once the paid action has already
    /// succeeded. Returns true if the backend confirmed the deduction.
    @discardableResult
    func spend(_ amount: Int, reason: String) async -> Bool {
        guard Purchases.isConfigured else { return false }
        let ok = await CreditBackendClient.spend(appUserID: appUserID, amount: amount, reason: reason)
        if ok { await reconcileAfterSpend() }
        return ok
    }

    /// First-launch starter credits. RevenueCat won't grant non-purchase
    /// credits, so the backend issues a one-time positive adjustment. Guarded
    /// locally so we ask at most once per install.
    ///
    /// NOTE (hardening TODO): the definitive dedupe must live server-side —
    /// the backend should check for a prior starter grant on this App User ID
    /// before adding credits. The local flag only prevents repeat calls from
    /// this install.
    func ensureStarterGrant() async {
        guard Purchases.isConfigured else { return }
        let key = "didRequestStarterGrant"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let ok = await CreditBackendClient.starterGrant(appUserID: appUserID)
        if ok {
            UserDefaults.standard.set(true, forKey: key)
            await reconcileAfterSpend()
        }
    }

    /// Re-sync the local balance with RevenueCat after a backend adjustment.
    func reconcileAfterSpend() async {
        guard Purchases.isConfigured else { return }
        Purchases.shared.invalidateVirtualCurrenciesCache()
        await refreshBalance()
    }
}
