import SwiftUI
import UIKit

/// Full results for one analysis. Used in three places: the end of the scan
/// flow, the Home tab's latest card, and History detail — all render the same
/// persisted `AnalysisRecord`, so nothing here can trigger a re-scan.
struct InsightView: View {
    let record: AnalysisRecord
    /// True only when rendered as the scan flow's `.results` phase, where the
    /// shared `ScanViewModel` already drives the screen — so Regenerate can
    /// transition in place. Home/History render this view pushed in a
    /// NavigationStack, so Regenerate there presents its own `ScanFlowView` to
    /// observe the generation phase and show the fresh result.
    var isInScanFlow = false

    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(DeepVisionRunner.self) private var deepVisionRunner
    @Environment(\.openURL) private var openURL

    @State private var shareCardSet: ShareCardSet?
    /// True while the Full Story photos load + panels render (the two quick
    /// cards are instant; the story set is what takes a moment).
    @State private var isPreparingShareCards = false
    @State private var showPaywall = false
    @State private var showAIDataSharingConsent = false
    @State private var paywallContext: PaywallView.Context = .general
    @State private var renderErrorMessage: String?
    /// Set when the report draft can't be opened because the device has no mail
    /// account — without this the button would just do nothing.
    @State private var mailUnavailable = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    narrative

                    superlativeGrid

                    VStack(spacing: Theme.Spacing.m) {
                        Button {
                            renderShareCards()
                        } label: {
                            if isPreparingShareCards {
                                HStack(spacing: Theme.Spacing.s) {
                                    ProgressView()
                                        .tint(Theme.Colors.background)
                                    Text("Preparing Cards…")
                                }
                            } else {
                                Label("Create Share Card", systemImage: "square.and.arrow.up")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isPreparingShareCards)

                        regenerateButton

                        deepAnalysisButton
                    }
                    .padding(.top, Theme.Spacing.s)

                    reportRow
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: paywallContext)
        }
        .sheet(isPresented: $showAIDataSharingConsent) {
            AIDataSharingConsentView {
                showAIDataSharingConsent = false
                performRegenerate()
            } onDecline: {
                showAIDataSharingConsent = false
            }
        }
        .sheet(item: $shareCardSet) { set in
            ShareCardPickerSheet(cards: set.cards)
        }
        .alert("Share card failed", isPresented: .init(
            get: { renderErrorMessage != nil },
            set: { if !$0 { renderErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renderErrorMessage ?? "")
        }
        .alert("No mail app set up", isPresented: $mailUnavailable) {
            Button("Copy Address") { UIPasteboard.general.string = SupportMail.address }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email \(SupportMail.address) and we'll look into it.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                PersonaChip(persona: record.persona)
                Spacer()
                Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(record.insight.headline)
                .font(Theme.Typography.display)
                .padding(.top, Theme.Spacing.s)

            HStack(spacing: Theme.Spacing.s) {
                // Which slice of the library this story is about (e.g. "April
                // 2024", an album name, or "Full history") — distinct from the
                // created date above, which is only when it was generated.
                Label(record.stats.scope.displayLabel, systemImage: "calendar")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if record.depth == .deep {
                    Label("Deep", systemImage: "sparkles")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.accentSoft, in: Capsule())
                }
            }
        }
        .padding(.top, Theme.Spacing.l)
    }

    /// Segmented insights render one card per narrative beat, with a matching
    /// photo (looked up on-device) under category-tagged segments. Older
    /// records and legacy backend responses have no segments and keep the
    /// single body card.
    @ViewBuilder
    private var narrative: some View {
        if let segments = record.insight.segments, !segments.isEmpty {
            let assetIDsPerSegment = SegmentPhotoResolver.assetIDsPerSegment(
                segments: segments,
                photoIndex: record.categoryPhotoIndex
            )
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    InsightSegmentCard(
                        segment: segment,
                        assetIDs: assetIDsPerSegment[index],
                        captions: record.photoCaptions ?? [:]
                    )
                }
            }
        } else {
            Text(record.insight.body)
                .font(Theme.Typography.body)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
                .themedCard()
        }
    }

    private var superlativeGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.m), GridItem(.flexible())],
            spacing: Theme.Spacing.m
        ) {
            ForEach(Array(record.insight.superlatives.enumerated()), id: \.element) { index, superlative in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(superlative.title.uppercased())
                        .font(Theme.Typography.label)
                        .tracking(1)
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))
                    Text(superlative.detail)
                        .font(Theme.Typography.headline)
                        .lineSpacing(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .padding(Theme.Spacing.m)
                .background(
                    Theme.Colors.cardCycle[index % Theme.Colors.cardCycle.count].opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card)
                )
            }
        }
    }

    /// Entry point into the hand-picked Deep Vision flow. Rendered only while
    /// that flow is open to users (`AnalysisKind.launchable`) — until then it is
    /// omitted entirely rather than shown as a disabled "coming soon" row, which
    /// App Store Review Guideline 2.1 treats as placeholder UI.
    @ViewBuilder
    private var deepAnalysisButton: some View {
        if AnalysisKind.launchable.contains(.handPicked) {
            if purchaseManager.canAfford(PurchaseManager.deepVisionCost) {
                Button {
                    Haptics.primary()
                    // Persona + stats inherited from this analysis; the flow is
                    // presented by RootView's cover (over the whole tab shell),
                    // so the run survives this screen going away.
                    deepVisionRunner.beginFlow(persona: record.persona, sourceStats: record.stats)
                } label: {
                    Label("Hand-Pick Photos to Read · \(PurchaseManager.deepVisionCost) gems", systemImage: "photo.badge.plus")
                }
                .buttonStyle(SoftButtonStyle())
            } else {
                Button {
                    Haptics.warning()
                    paywallContext = .deepVision(have: purchaseManager.gemBalance)
                    showPaywall = true
                } label: {
                    Label("Hand-Pick Photos to Read · needs \(PurchaseManager.deepVisionCost) gems", systemImage: "photo.badge.plus")
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    /// Paid "fresh take": re-writes the narrative over the same stats with an
    /// advancing variation seed (see `ScanViewModel.regenerate`). Always shown —
    /// the results screen is the natural place to ask for a different read.
    private var regenerateButton: some View {
        // A deep record regenerates deep (long story, 5 gems); standard, 1.
        let cost = PurchaseManager.cost(for: record.depth ?? .standard)
        return Button {
            regenerate()
        } label: {
            Label(
                "Get a fresh take · \(cost) \(cost == 1 ? "gem" : "gems")",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .buttonStyle(SoftButtonStyle())
    }

    private func regenerate() {
        let cost = PurchaseManager.cost(for: record.depth ?? .standard)
        // Client-side affordability check is UX only; the backend is the
        // authoritative gate (deduct-after-success), same as a normal analysis.
        guard purchaseManager.canAfford(cost) else {
            Haptics.warning()
            paywallContext = .analysis(cost: cost, have: purchaseManager.gemBalance)
            showPaywall = true
            return
        }
        guard AIDataSharingConsent.isGranted else {
            showAIDataSharingConsent = true
            return
        }
        performRegenerate()
    }

    private func performRegenerate() {
        Haptics.primary()
        scanViewModel.regenerate(from: record, appUserID: purchaseManager.appUserID)
        // Inside the scan flow the shared view model already drives this
        // screen; from Home/History we present the flow (RootView's cover,
        // over the whole tab shell) to observe generation + result.
        // `regenerate` has already set the phase, so it opens straight onto
        // "writing your story".
        if !isInScanFlow {
            scanViewModel.presentFlow()
        }
    }

    /// Reporting an analysis the AI got wrong. App Store Review Guideline 1.2
    /// wants a reporting mechanism in any app that generates content; this is
    /// it, and it's the reason the results screen is the place for it — the
    /// content being reported is right above.
    ///
    /// Deliberately quiet: caption-sized, centered, below the actions. A roast
    /// landing badly is rare, and an escape hatch styled like a primary button
    /// would suggest otherwise.
    private var reportRow: some View {
        Button {
            Haptics.tap()
            guard let url = SupportMail.contentReportURL(for: record) else { return }
            // A device with no mail account silently refuses `mailto:`, which
            // would leave this button looking broken — fall back to showing the
            // address instead.
            openURL(url) { opened in
                if !opened { mailUnavailable = true }
            }
        } label: {
            Label("Report this analysis", systemImage: "exclamationmark.bubble")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Theme.Spacing.m)
    }

    private func renderShareCards() {
        // Share cards are unlimited in the gem model — no gating here.
        guard !isPreparingShareCards else { return }
        Haptics.tap()
        isPreparingShareCards = true
        Task { @MainActor in
            defer { isPreparingShareCards = false }
            do {
                shareCardSet = try await ShareCardSet.render(for: record)
            } catch {
                renderErrorMessage = error.localizedDescription
            }
        }
    }
}
