import SwiftUI

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

    @State private var shareCardSet: ShareCardSet?
    @State private var showPaywall = false
    @State private var paywallContext: PaywallView.Context = .general
    @State private var showDeepAnalysis = false
    @State private var showRegenerateFlow = false
    @State private var renderErrorMessage: String?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    narrative

                    if record.insight.isPreview == true {
                        Label(
                            "Preview insight — written on your device while the AI writer takes a breather.",
                            systemImage: "wand.and.stars.inverse"
                        )
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    superlativeGrid

                    VStack(spacing: Theme.Spacing.m) {
                        Button {
                            renderShareCard()
                        } label: {
                            Label("Create Share Card", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        regenerateButton

                        deepAnalysisButton
                    }
                    .padding(.top, Theme.Spacing.s)
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: paywallContext)
        }
        .sheet(isPresented: $showDeepAnalysis) {
            DeepAnalysisConsentView(persona: record.persona, sourceStats: record.stats)
        }
        .fullScreenCover(isPresented: $showRegenerateFlow) {
            // From Home/History: show the in-flight generation and the fresh
            // result. `regenerate(from:)` has already set the phase before this
            // presents, so the flow opens straight onto "writing your story".
            ScanFlowView()
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

    @ViewBuilder
    private var deepAnalysisButton: some View {
        // Gated on credits now, not Pro. The affordability check is UX only;
        // the actual 5-credit charge is issued by the backend after a
        // successful Deep Vision run (see DeepAnalysisConsentView).
        if purchaseManager.canAfford(PurchaseManager.deepVisionCost) {
            Button {
                showDeepAnalysis = true
            } label: {
                Label("Hand-Pick Photos to Read · \(PurchaseManager.deepVisionCost) credits", systemImage: "photo.badge.plus")
            }
            .buttonStyle(SoftButtonStyle())
        } else {
            Button {
                paywallContext = .deepVision(have: purchaseManager.creditBalance)
                showPaywall = true
            } label: {
                Label("Hand-Pick Photos to Read · needs \(PurchaseManager.deepVisionCost) credits", systemImage: "photo.badge.plus")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    /// Paid "fresh take": re-writes the narrative over the same stats with an
    /// advancing variation seed (see `ScanViewModel.regenerate`). Always shown —
    /// the results screen is the natural place to ask for a different read.
    private var regenerateButton: some View {
        // A deep record regenerates deep (long story, 5 credits); standard, 1.
        let cost = PurchaseManager.cost(for: record.depth ?? .standard)
        return Button {
            regenerate()
        } label: {
            Label(
                "Get a fresh take · \(cost) \(cost == 1 ? "credit" : "credits")",
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
            paywallContext = .analysis(have: purchaseManager.creditBalance)
            showPaywall = true
            return
        }
        scanViewModel.regenerate(from: record, appUserID: purchaseManager.appUserID)
        // Inside the scan flow the shared view model already drives this screen;
        // from Home/History we present the flow to observe generation + result.
        if !isInScanFlow {
            showRegenerateFlow = true
        }
    }

    private func renderShareCard() {
        // Share cards are unlimited in the credit model — no gating here.
        do {
            let classic = try ShareCardRenderer()
                .renderCard(insight: record.insight, stats: record.stats)
            let editorial = try AltShareCardRenderer()
                .renderCard(insight: record.insight, stats: record.stats)
            shareCardSet = ShareCardSet(cards: [
                RenderedShareCard(id: "classic", title: "Classic", image: classic),
                RenderedShareCard(id: "editorial", title: "Editorial", image: editorial),
            ])
        } catch {
            renderErrorMessage = error.localizedDescription
        }
    }
}
