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
            DeepAnalysisConsentView(sourceRecord: record)
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

            // Which slice of the library this story is about (e.g. "April
            // 2024", an album name, or "Full history") — distinct from the
            // created date above, which is only when it was generated.
            Label(record.stats.scope.displayLabel, systemImage: "calendar")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
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
            let assetIDsPerSegment = deduplicatedAssetIDs(for: segments)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    InsightSegmentCard(
                        segment: segment,
                        assetIDs: assetIDsPerSegment[index]
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

    /// Candidate photos for each segment, in render order, de-duplicated
    /// across the whole narrative: once a photo is claimed by one beat it's
    /// pushed to the back of later beats' candidate lists, so two segments
    /// that share a category (e.g. two "screenshot" beats) surface different
    /// photos when the category indexed more than one. Each key holds up to
    /// two assets (see `StatsAggregator.photoIndex`), which covers the common
    /// case; if a category has only one photo, that lone photo is reused
    /// rather than showing nothing. Untagged/unindexed segments stay empty
    /// (text-only card).
    private func deduplicatedAssetIDs(for segments: [Insight.Segment]) -> [[String]] {
        var claimed: Set<String> = []
        return segments.map { segment in
            guard let category = segment.category,
                  let candidates = record.categoryPhotoIndex?[category],
                  !candidates.isEmpty else { return [] }

            // Prefer photos no earlier beat has already shown.
            let fresh = candidates.filter { !claimed.contains($0) }
            let ordered = fresh + candidates.filter { claimed.contains($0) }

            // Claim the one the card will most likely display (its first
            // resolvable candidate) so the next beat avoids it.
            if let first = ordered.first { claimed.insert(first) }
            return ordered
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
                Label("Deep Photo Analysis · \(PurchaseManager.deepVisionCost) credits", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
        } else {
            Button {
                paywallContext = .deepVision(have: purchaseManager.creditBalance)
                showPaywall = true
            } label: {
                Label("Deep Photo Analysis · needs \(PurchaseManager.deepVisionCost) credits", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    /// Paid "fresh take": re-writes the narrative over the same stats with an
    /// advancing variation seed (see `ScanViewModel.regenerate`). Always shown —
    /// the results screen is the natural place to ask for a different read.
    private var regenerateButton: some View {
        Button {
            regenerate()
        } label: {
            Label(
                "Get a fresh take · \(PurchaseManager.analysisCost) credit",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .buttonStyle(SoftButtonStyle())
    }

    private func regenerate() {
        // Client-side affordability check is UX only; the backend is the
        // authoritative gate (deduct-after-success), same as a normal analysis.
        guard purchaseManager.canAfford(PurchaseManager.analysisCost) else {
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
