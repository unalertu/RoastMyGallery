import SwiftUI
import StoreKit

/// Screen 5: Pro upsell — calm and matter-of-fact, no urgency tactics.
/// Pro is about *scope*: full history, deep photo analysis, unlimited cards.
/// Persona choice is free and never appears here.
struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.l) {
                        VStack(spacing: Theme.Spacing.s) {
                            Text("See the whole picture")
                                .font(Theme.Typography.display)
                                .multilineTextAlignment(.center)
                            Text("Pro widens the lens — same voices, much more to work with.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.l)

                        VStack(spacing: Theme.Spacing.m) {
                            benefit(
                                icon: "clock.arrow.circlepath",
                                tint: Theme.Colors.powderBlue,
                                title: "Your full photo history",
                                detail: "Every year of your library, not just the last three months."
                            )
                            benefit(
                                icon: "sparkles",
                                tint: Theme.Colors.dustyRose,
                                title: "Deep photo analysis",
                                detail: "Hand-pick up to 30 photos for individual, photo-by-photo commentary."
                            )
                            benefit(
                                icon: "square.and.arrow.up",
                                tint: Theme.Colors.sage,
                                title: "Unlimited share cards",
                                detail: "Make and share as many cards as you like."
                            )
                        }

                        if purchaseManager.isLoadingProducts {
                            ProgressView()
                                .padding(Theme.Spacing.m)
                        } else if purchaseManager.products.isEmpty {
                            // Products load from RoastMyGallery.storekit locally.
                            // TODO: set real product IDs in PurchaseManager.ProductID
                            // and App Store Connect.
                            Text("Products unavailable. Check StoreKit configuration.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        } else {
                            VStack(spacing: Theme.Spacing.m) {
                                ForEach(purchaseManager.products, id: \.id) { product in
                                    productButton(product)
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
            .onChange(of: purchaseManager.entitlements.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private func benefit(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.6))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .themedCard()
    }

    private func productButton(_ product: Product) -> some View {
        Button {
            Task { await purchaseManager.purchase(product) }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(product.displayName)
                Text(product.displayPrice)
                    .font(Theme.Typography.caption)
                    .opacity(0.85)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(purchaseManager.purchaseInFlight)
    }
}
