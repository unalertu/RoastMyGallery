import SwiftUI

/// Full results for one analysis. Used in three places: the end of the scan
/// flow, the Home tab's latest card, and History detail — all render the same
/// persisted `AnalysisRecord`, so nothing here can trigger a re-scan.
struct InsightView: View {
    let record: AnalysisRecord

    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var shareCardSet: ShareCardSet?
    @State private var showPaywall = false
    @State private var showDeepAnalysis = false
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
                            systemImage: "sparkles.slash"
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

                        deepAnalysisButton
                    }
                    .padding(.top, Theme.Spacing.s)
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showDeepAnalysis) {
            DeepAnalysisConsentView(persona: record.persona)
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
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    InsightSegmentCard(
                        segment: segment,
                        assetIDs: assetIDs(for: segment)
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

    /// Candidate photos for a segment's category — empty (text-only card)
    /// when the segment is untagged or the scan indexed no photo for it.
    private func assetIDs(for segment: Insight.Segment) -> [String] {
        guard let category = segment.category else { return [] }
        return record.categoryPhotoIndex?[category] ?? []
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
        if purchaseManager.entitlements.canUseDeepAnalysis {
            Button {
                showDeepAnalysis = true
            } label: {
                Label("Deep Photo Analysis", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
        } else {
            Button {
                showPaywall = true
            } label: {
                Label("Unlock Deep Photo Analysis", systemImage: "sparkles")
            }
            .buttonStyle(SoftButtonStyle())
        }
    }

    private func renderShareCard() {
        // TODO: enforce entitlements.shareCardLimit for free users (persist a
        // "cards generated" counter, route to paywall when exceeded).
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
