import Foundation
import RevenueCat
import Observation

/// Single source of truth for monetization — now backed by RevenueCat +
/// Virtual Currencies, not raw StoreKit. Views read the gem balance and
/// subscription status from here and never touch the SDK directly.
///
/// Model:
/// - Gems are a RevenueCat **Virtual Currency** (code `CRD`). RevenueCat is
///   the authoritative balance: purchases (consumable packs, subscription
///   renewals) *grant* gems automatically via dashboard product
///   associations. This client only ever *reads* the balance.
/// - Spending is NOT possible from the SDK by design. Every deduction is a
///   negative adjustment issued server-side by our Vercel backend (which
///   holds the RevenueCat secret key), folded into the paid endpoints
///   themselves — `backend/api/insight.js` and `backend/api/deep-vision.js`.
///   After a spend we re-read the balance.
///
/// ─────────────────────────────────────────────────────────────────────────
/// CONFIG — replace these placeholders once the RevenueCat dashboard is set up:
///   • `publicAPIKey`      → your RevenueCat *public* SDK key (safe to embed).
///   • `gemCurrencyCode`→ must equal the Virtual Currency code you create.
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
    static let publicAPIKey = "appl_LXxsWuCHpLypyIrEPTMOAnIIAVF"

    /// Virtual Currency code configured in RevenueCat (Product Catalog →
    /// Virtual Currencies). Must match exactly.
    static let gemCurrencyCode = "CRD"

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

    // MARK: - Gem costs (app-side constants; the real gate is RevenueCat)
    // `nonisolated` so pure constants/helpers can be read from non-main-actor
    // contexts (e.g. PaywallView.Context) without a Swift 6 isolation error.

    nonisolated static let analysisCost = 1
    /// Deep analysis: the date-range scan with the long story + photo captions.
    nonisolated static let deepAnalysisCost = 5
    /// Hand-picked Deep Vision: the user-selected ≤30 photo batch.
    nonisolated static let deepVisionCost = 5
    nonisolated static let starterGems = 3

    /// Cost of one analysis run at the given depth.
    nonisolated static func cost(for depth: AnalysisDepth) -> Int {
        depth == .deep ? deepAnalysisCost : analysisCost
    }

    /// Gems granted per purchase, mirrored client-side purely for paywall
    /// framing ("10 gems = 10 analyses"). The authoritative grant is the
    /// associated-product amount configured in the RevenueCat dashboard — keep
    /// these in sync with it.
    nonisolated static func advertisedGems(forProductID id: String) -> Int? {
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
    private(set) var gemBalance = 0
    /// Whether the monthly gem subscription is active. Drives the
    /// "Subscriber" badge only — it grants no features beyond the gems it
    /// tops up. Independent from the balance.
    private(set) var isSubscribed = false
    private(set) var isLoadingOfferings = false
    private(set) var purchaseInFlight = false
    var lastError: String?

    /// Populated after a successful purchase so the UI can show a celebration.
    struct PurchaseResult {
        let gemsAdded: Int
        let newBalance: Int
    }
    var lastPurchaseResult: PurchaseResult?

    /// Stable RevenueCat App User ID for this install — a Keychain-persisted ID
    /// (see `KeychainAppUserID`) that survives app deletion on the same device,
    /// so the gem balance is preserved across a reinstall. The backend uses it
    /// to target the right customer for spends/grants.
    var appUserID: String { Purchases.isConfigured ? Purchases.shared.appUserID : "unconfigured" }

    private var customerInfoTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Call once, before any `Purchases.shared` use (see RoastMyGalleryApp).
    ///
    /// Configures with a **stable, Keychain-persisted App User ID** (see
    /// `KeychainAppUserID`) instead of RevenueCat's default anonymous ID. The
    /// anonymous ID lives in UserDefaults and is wiped when the app is deleted,
    /// so an anonymous user loses their (paid) gem balance on reinstall. A
    /// Keychain-backed ID survives app deletion on the same device, so a delete
    /// + reinstall resolves the same RevenueCat customer and the balance is
    /// preserved. (Cross-device / new-phone continuity still needs a real
    /// login — see `restorePurchases`.)
    static func configure() {
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: publicAPIKey, appUserID: KeychainAppUserID.getOrCreate())
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
    /// balance, and grant first-launch starter gems if this user is new.
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
    }

    // MARK: - Balance (Virtual Currency)

    /// Cache-first, no network — call before rendering for an instant balance.
    func primeCachedBalance() {
        guard Purchases.isConfigured,
              let cached = Purchases.shared.cachedVirtualCurrencies else { return }
        gemBalance = cached.all[Self.gemCurrencyCode]?.balance ?? gemBalance
    }

    /// Authoritative fetch from RevenueCat. Falls back to the cached value on
    /// network failure rather than zeroing a real balance.
    func refreshBalance() async {
        guard Purchases.isConfigured else { return }
        if let server = await fetchServerBalance() {
            gemBalance = server
        } else {
            primeCachedBalance()
        }
    }

    /// One authoritative CRD read, or nil when it can't be determined (SDK
    /// unconfigured / network failure). Callers decide how to merge it.
    private func fetchServerBalance() async -> Int? {
        guard Purchases.isConfigured else { return nil }
        do {
            let currencies = try await Purchases.shared.virtualCurrencies()
            return currencies.all[Self.gemCurrencyCode]?.balance ?? 0
        } catch {
            return nil
        }
    }

    /// UX-only affordability check. The real gate is RevenueCat rejecting an
    /// over-spend server-side; this just lets us route to the paywall early.
    func canAfford(_ amount: Int) -> Bool { gemBalance >= amount }

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
            // RevenueCat applies the gem grant server-side; drop the stale
            // cache and re-read.
            let balanceBefore = gemBalance
            Purchases.shared.invalidateVirtualCurrenciesCache()
            await refreshBalance()
            let gemsAdded = gemBalance - balanceBefore
            // Fallback: if the delta is zero (race / cache), use the product's
            // advertised amount so the celebration still makes sense.
            let productID = package.storeProduct.productIdentifier
            let displayGems = gemsAdded > 0
                ? gemsAdded
                : (Self.advertisedGems(forProductID: productID) ?? gemsAdded)
            lastPurchaseResult = PurchaseResult(
                gemsAdded: displayGems,
                newBalance: gemBalance
            )
        } catch ErrorCode.paymentPendingError {
            registerPendingPurchase()
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Ask to Buy / deferred transactions: not a failure. The CustomerInfo
    /// stream applies the gems automatically once a parent approves — nothing
    /// to do here but say so. One function on purpose, so the real catch in
    /// `purchase(_:)` and the DEBUG simulator below can never drift apart.
    private func registerPendingPurchase() {
        lastError = "This purchase is waiting for approval. Your gems will be added automatically once it's approved."
    }

    #if DEBUG
    /// DEBUG-ONLY (compiled out of Release by this `#if DEBUG`): drives the
    /// exact pending-purchase handling a real Ask to Buy hits — same handler
    /// the `paymentPendingError` catch calls, same message, same `lastError`
    /// surface on the paywall. Exists because Apple provides no sandbox
    /// switch to trigger a real deferred transaction on demand.
    ///
    /// STRIP BEFORE SHIPPING: remove this and the paywall's `debugTools`
    /// section (PaywallView.swift) — or at minimum re-confirm both are still
    /// `#if DEBUG`-gated — before the final App Store archive.
    func debugSimulatePaymentPending() {
        // Mirror the state `purchase(_:)` resets before its catch runs.
        lastPurchaseResult = nil
        registerPendingPurchase()
    }
    #endif

    enum RestoreResult: Equatable {
        case restoredSubscription
        case noPurchases
        case failed(String)

        /// User-facing outcome message, shared by every restore entry point
        /// (Settings and the paywall) so restoring is never a silent no-op.
        var userMessage: String {
            switch self {
            case .restoredSubscription:
                return "Your subscription has been restored. Monthly gems will keep topping up."
            case .noPurchases:
                return "No subscription was found on this Apple ID. (Consumable gem packs can't be restored — see support.)"
            case .failed(let reason):
                return reason
            }
        }
    }

    /// Restores the *subscription* entitlement. Consumable gem packs cannot
    /// be restored by design — once granted, the gems live in RevenueCat's
    /// balance for this App User ID. That ID is Keychain-persisted
    /// (`KeychainAppUserID`), so the balance already survives a delete +
    /// reinstall on the SAME device. Cross-device continuity (a new phone)
    /// still requires logging the user into a stable RevenueCat identity — the
    /// Keychain ID does not reliably travel between devices. See known
    /// limitations.
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

    // MARK: - Grants (via our backend, which holds the secret key)

    /// First-launch starter gems. RevenueCat won't grant non-purchase
    /// gems, so the backend issues a one-time positive adjustment. Guarded
    /// locally so we ask at most once per install.
    ///
    /// NOTE (hardening TODO): the definitive dedupe must live server-side —
    /// the backend should check for a prior starter grant on this App User ID
    /// before adding gems. The local flag only prevents repeat calls from
    /// this install.
    func ensureStarterGrant() async {
        guard Purchases.isConfigured else { return }
        let key = "didRequestStarterGrant"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let ok = await GemBackendClient.starterGrant(appUserID: appUserID)
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

    /// Reflect a spend the backend has *already* charged (deduct-after-success):
    /// drop the local balance immediately for instant UI feedback, then
    /// reconcile with RevenueCat.
    ///
    /// The key subtlety this exists to solve: a server-side Virtual Currency
    /// adjustment is not always readable by the client the instant it commits
    /// (read-after-write lag), so a naive re-read right after a spend can
    /// return the *pre-spend* balance and bounce the number straight back up —
    /// making it look like the gem never came off. A spend can only ever
    /// lower the balance, so we clamp the reconcile with `min`: a fresh server
    /// read is accepted, but a stale (higher) one can't undo the optimistic
    /// deduction. A later full refresh (customerInfoStream / bootstrap)
    /// corrects any residual drift.
    func reflectSpend(_ amount: Int) async {
        let optimistic = max(0, gemBalance - amount)
        gemBalance = optimistic
        guard Purchases.isConfigured else { return }
        Purchases.shared.invalidateVirtualCurrenciesCache()
        if let server = await fetchServerBalance() {
            gemBalance = min(server, optimistic)
        }
    }
}
