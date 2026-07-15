import Foundation
import StoreKit
import Observation

/// Single source of truth for StoreKit 2 products and entitlements.
/// ALL paywall/gating decisions go through `entitlements` — views must never
/// re-derive Pro status on their own.
@MainActor
@Observable
final class PurchaseManager {
    // MARK: - Product IDs
    // TODO: Replace with your real product IDs from App Store Connect, and
    // mirror them in RoastMyGallery.storekit for local testing.
    enum ProductID: String, CaseIterable {
        /// Primary monetization: one-time lifetime unlock.
        case proLifetime = "com.example.roastmygallery.pro.lifetime"
        /// Secondary: monthly subscription.
        case proMonthly = "com.example.roastmygallery.pro.monthly"
    }

    /// Everything the app is allowed to gate on, derived in exactly one place.
    /// Pro gates on *scope* only — history depth, deep analysis, card limit.
    /// Persona choice is never gated.
    struct Entitlements: Equatable {
        var isPro: Bool = false

        var analysisScope: AnalysisScope { isPro ? .fullHistory : .lastThreeMonths }
        var canUseDeepAnalysis: Bool { isPro }
        var canGenerateUnlimitedCards: Bool { isPro }
        /// Free tier: 1 shareable card total.
        var shareCardLimit: Int? { isPro ? nil : 1 }
    }

    private(set) var entitlements = Entitlements()
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var purchaseInFlight = false
    var lastError: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        // Listen for transactions from outside the app (Ask to Buy, renewals,
        // purchases on another device). This manager is created once in
        // RoastMyGalleryApp and lives for the app's lifetime, so the listener
        // is never torn down (the weak capture ends the loop if it ever is).
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(transactionResult: update)
            }
        }
    }

    // MARK: - Loading

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
                .sorted { $0.price < $1.price }
        } catch {
            lastError = "Couldn't load products: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }

    /// Recomputes entitlements from StoreKit's current-entitlement state.
    func refreshEntitlements() async {
        var isPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if ProductID(rawValue: transaction.productID) != nil, transaction.revocationDate == nil {
                isPro = true
            }
        }
        entitlements = Entitlements(isPro: isPro)
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Outcome of a restore, so callers can show real success/failure feedback
    /// rather than guessing from `lastError`.
    enum RestoreResult: Equatable {
        case restoredPro
        case noPurchases
        case failed(String)
    }

    @discardableResult
    func restorePurchases() async -> RestoreResult {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            let message = "Restore failed: \(error.localizedDescription)"
            lastError = message
            return .failed(message)
        }
        await refreshEntitlements()
        return entitlements.isPro ? .restoredPro : .noPurchases
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
        await refreshEntitlements()
    }
}
