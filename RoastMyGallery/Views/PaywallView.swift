import SwiftUI
import RevenueCat

/// Credit store — buy one-time credit packs or subscribe for a monthly top-up.
/// Data comes from the current RevenueCat Offering; the pastel DesignSystem is
/// unchanged. Framing is matter-of-fact: "what does X credits get me."
struct PaywallView: View {
    /// Why the paywall was opened — drives the header message and whether it
    /// auto-dismisses once the user can afford the action they wanted.
    enum Context: Equatable {
        case general
        case analysis(have: Int)
        case deepVision(have: Int)
        case lockedMode(name: String)

        var message: String? {
            switch self {
            case .general:
                return nil
            case .analysis(let have):
                return "You need \(PurchaseManager.analysisCost) credit for this analysis — you have \(have)."
            case .deepVision(let have):
                return "You need \(PurchaseManager.deepVisionCost) credits for a Deep Vision batch — you have \(have)."
            case .lockedMode(let name):
                return "Unlock \(name) — and every analysis mode — with your first credit purchase."
            }
        }
    }

    var context: Context = .general

    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSuccess = false
    @State private var successCredits = 0
    @State private var successBalance = 0

    private var packages: [Package] {
        purchaseManager.offerings?.current?.availablePackages ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.l) {
                        headerBlock
                        creditExplainer

                        if purchaseManager.isLoadingOfferings {
                            ProgressView()
                                .padding(Theme.Spacing.m)
                        } else if packages.isEmpty {
                            // Offering loads from RevenueCat. Until the dashboard
                            // products + Offering exist (and the public key is
                            // set), this stays empty — see CONFIG in PurchaseManager.
                            Text("Products unavailable. Check the RevenueCat Offering and API key.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                            VStack(spacing: Theme.Spacing.m) {
                                ForEach(packages, id: \.identifier) { package in
                                    packageCard(package)
                                }
                            }
                        }

                        Button("Restore Purchases") {
                            Task { await purchaseManager.restorePurchases() }
                        }
                        .buttonStyle(QuietButtonStyle())

                        if let error = purchaseManager.lastError {
                            Text(error)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.danger)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .onChange(of: purchaseManager.lastPurchaseResult?.newBalance) { _, _ in
                // Show the celebration screen when a purchase succeeds.
                if let result = purchaseManager.lastPurchaseResult {
                    successCredits = result.creditsAdded
                    successBalance = result.newBalance
                    showSuccess = true
                    purchaseManager.lastPurchaseResult = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showSuccess) {
            PurchaseSuccessView(
                creditsAdded: successCredits,
                newBalance: successBalance,
                onDismiss: {
                    showSuccess = false
                    // For context-specific flows, dismiss paywall too.
                    switch context {
                    case .analysis where purchaseManager.canAfford(PurchaseManager.analysisCost),
                         .deepVision where purchaseManager.canAfford(PurchaseManager.deepVisionCost):
                        dismiss()
                    case .general:
                        break       // stay on paywall so user can buy more
                    default:
                        break
                    }
                }
            )
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Get credits")
                .font(Theme.Typography.display)
                .multilineTextAlignment(.center)

            if let message = context.message {
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Credits power your analyses. You have \(purchaseManager.creditBalance).")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Theme.Spacing.l)
    }

    /// "What does a credit get me" — the framing the paywall is built around.
    private var creditExplainer: some View {
        VStack(spacing: Theme.Spacing.m) {
            explainerRow(
                icon: "sparkle",
                tint: Theme.Colors.powderBlue,
                title: "\(PurchaseManager.analysisCost) credit = 1 gallery analysis",
                detail: "Full-history scan plus an AI-written insight."
            )
            explainerRow(
                icon: "sparkles",
                tint: Theme.Colors.dustyRose,
                title: "\(PurchaseManager.deepVisionCost) credits = 1 Deep Vision batch",
                detail: "Photo-by-photo commentary on up to 30 hand-picked photos."
            )
        }
        .themedCard()
    }

    private func explainerRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle().fill(tint.opacity(0.6)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title).font(Theme.Typography.headline)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Package card

    private func packageCard(_ package: Package) -> some View {
        let productID = package.storeProduct.productIdentifier
        let credits = PurchaseManager.advertisedCredits(forProductID: productID)
        let isSub = PurchaseManager.isSubscription(productID: productID)

        return Button {
            Task { await purchaseManager.purchase(package) }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                if let credits {
                    Text(isSub ? "\(credits) credits / month" : "\(credits) credits")
                        .font(Theme.Typography.headline)
                    Text(creditFraming(credits: credits, isSub: isSub))
                        .font(Theme.Typography.caption)
                        .opacity(0.9)
                } else {
                    Text(package.storeProduct.localizedTitle)
                        .font(Theme.Typography.headline)
                }
                Text(isSub
                     ? "\(package.storeProduct.localizedPriceString) / month · renews automatically"
                     : package.storeProduct.localizedPriceString)
                    .font(Theme.Typography.caption)
                    .opacity(0.85)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(purchaseManager.purchaseInFlight)
    }

    /// "10 credits = 10 analyses, or 2 deep-vision batches".
    private func creditFraming(credits: Int, isSub: Bool) -> String {
        let analyses = credits / PurchaseManager.analysisCost
        let batches = credits / PurchaseManager.deepVisionCost
        let base = "\(analyses) analyses, or \(batches) deep-vision \(batches == 1 ? "batch" : "batches")"
        return isSub ? "Each month: \(base)" : base
    }
}
