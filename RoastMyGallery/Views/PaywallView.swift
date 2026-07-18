import SwiftUI
import RevenueCat

/// Gem store — buy one-time gem packs.
/// Data comes from the current RevenueCat Offering; the pastel DesignSystem is
/// unchanged. Framing is matter-of-fact: "what does X gems get me."
struct PaywallView: View {
    /// Why the paywall was opened — drives the header message and whether it
    /// auto-dismisses once the user can afford the action they wanted.
    /// `analysis` carries the actual cost of the run that was blocked (1 gem
    /// standard, 5 deep), so the message and the auto-dismiss threshold always
    /// match what the user came to pay for.
    enum Context: Equatable {
        case general
        case analysis(cost: Int, have: Int)
        case deepVision(have: Int)

        var message: String? {
            switch self {
            case .general:
                return nil
            case .analysis(let cost, let have):
                return "You need \(cost) \(cost == 1 ? "gem" : "gems") for this analysis — you have \(have)."
            case .deepVision(let have):
                return "You need \(PurchaseManager.deepVisionCost) gems for a Deep Vision batch — you have \(have)."
            }
        }
    }

    var context: Context = .general

    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSuccess = false
    @State private var successGems = 0
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
                        gemExplainer

                        if purchaseManager.isLoadingOfferings {
                            ProgressView()
                                .padding(Theme.Spacing.m)
                        } else if packages.isEmpty {
                            // Offering loads from RevenueCat. Until the dashboard
                            // products + Offering exist (and the public key is
                            // set), this stays empty — see CONFIG in PurchaseManager.
                            Text("Couldn't load the gem packs. Check your connection and try again in a moment.")
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

                        if let error = purchaseManager.lastError {
                            Text(error)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.danger)
                                .multilineTextAlignment(.center)
                        }

                        #if DEBUG
                        debugTools
                        #endif
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
                    successGems = result.gemsAdded
                    successBalance = result.newBalance
                    showSuccess = true
                    purchaseManager.lastPurchaseResult = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showSuccess) {
            PurchaseSuccessView(
                gemsAdded: successGems,
                newBalance: successBalance,
                onDismiss: {
                    showSuccess = false
                    // For context-specific flows, dismiss the paywall too —
                    // but only once the user can afford the action they
                    // actually came for (its real cost, not just 1 gem).
                    switch context {
                    case .analysis(let cost, _) where purchaseManager.canAfford(cost):
                        dismiss()
                    case .deepVision where purchaseManager.canAfford(PurchaseManager.deepVisionCost):
                        dismiss()
                    case .general:
                        break       // stay on paywall so user can buy more
                    default:
                        break       // still short — stay so they can top up
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
            Text("Get gems")
                .font(Theme.Typography.display)
                .multilineTextAlignment(.center)

            if let message = context.message {
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Gems power your analyses. You have \(purchaseManager.gemBalance).")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, Theme.Spacing.l)
    }

    /// "What does a gem get me" — the framing the paywall is built around.
    private var gemExplainer: some View {
        VStack(spacing: Theme.Spacing.m) {
            explainerRow(
                icon: "diamond.fill",
                tint: Theme.Colors.powderBlue,
                title: "\(PurchaseManager.analysisCost) gem = 1 gallery analysis",
                detail: "Full-history scan plus an AI-written insight."
            )
            explainerRow(
                icon: "diamond.fill",
                tint: Theme.Colors.dustyRose,
                title: "\(PurchaseManager.deepVisionCost) gems = 1 Deep Vision batch",
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
        let gems = PurchaseManager.advertisedGems(forProductID: productID)

        return Button {
            Task { await purchaseManager.purchase(package) }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                if let badge = PurchaseManager.promoBadge(forProductID: productID) {
                    Text(badge)
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.background, in: Capsule())
                }
                if let gems {
                    Text("\(gems) gems")
                        .font(Theme.Typography.headline)
                    Text(gemFraming(gems: gems))
                        .font(Theme.Typography.caption)
                        .opacity(0.9)
                } else {
                    Text(package.storeProduct.localizedTitle)
                        .font(Theme.Typography.headline)
                }
                Text(package.storeProduct.localizedPriceString)
                    .font(Theme.Typography.caption)
                    .opacity(0.85)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(purchaseManager.purchaseInFlight)
    }

    /// "20 gems = 20 analyses, or 4 deep-vision batches".
    private func gemFraming(gems: Int) -> String {
        let analyses = gems / PurchaseManager.analysisCost
        let batches = gems / PurchaseManager.deepVisionCost
        return "\(analyses) analyses, or \(batches) deep-vision \(batches == 1 ? "batch" : "batches")"
    }

    // MARK: - DEBUG-only dev tools

    #if DEBUG
    /// Dev-only panel, compiled out of Release builds entirely. Simulates the
    /// Ask to Buy pending outcome through the REAL PurchaseManager handler
    /// (see `debugSimulatePaymentPending`) so the message above renders
    /// exactly as a real deferred purchase would show it — Apple offers no
    /// sandbox switch to trigger one on demand.
    ///
    /// STRIP BEFORE SHIPPING: remove this section and
    /// `PurchaseManager.debugSimulatePaymentPending()` — or at minimum
    /// re-confirm both are still `#if DEBUG`-gated — before the final
    /// App Store archive.
    private var debugTools: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("DEBUG BUILD ONLY")
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.danger)
            Button("Simulate Ask to Buy (pending purchase)") {
                purchaseManager.debugSimulatePaymentPending()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.danger)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.m)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.button)
                .stroke(
                    Theme.Colors.danger.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .padding(.top, Theme.Spacing.m)
    }
    #endif
}
