import SwiftUI

/// Tab 1 — the app's entry point. Shows the latest analysis as a tappable
/// summary card (with a "New Analysis" action), or a friendly first-run
/// empty state with the scan call-to-action.
struct HomeView: View {
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showScanFlow = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header

                        if let latest = history.latest {
                            latestCard(latest)

                            quickStatsDashboard(latest.stats)

                            Button("New Analysis") { startScan() }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            emptyState
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .navigationDestination(for: AnalysisRecord.self) { record in
                if record.deepVision != nil {
                    DeepVisionRecordView(record: record)
                } else {
                    InsightView(record: record)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showScanFlow) {
            ScanFlowView()
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func startScan() {
        scanViewModel.prepareForNewScan()
        showScanFlow = true
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Roast My Gallery")
                    .font(Theme.Typography.display)
                Text(history.latest.map { "Last analyzed \($0.createdAt.formatted(.relative(presentation: .named)))" }
                     ?? "Your camera roll has opinions about you")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.m)
            creditPill
        }
        .padding(.top, Theme.Spacing.l)
    }

    /// Compact, always-visible credit balance. Tapping opens the credit store.
    private var creditPill: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                Text("\(purchaseManager.creditBalance)")
                    .font(Theme.Typography.headline)
            }
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(purchaseManager.creditBalance) credits. Tap to get more.")
    }

    /// Summary of the most recent analysis; tapping opens the full results.
    private func latestCard(_ record: AnalysisRecord) -> some View {
        NavigationLink(value: record) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    PersonaChip(persona: record.persona)
                    Spacer()
                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text(record.insight.headline)
                    .font(Theme.Typography.title)
                    .multilineTextAlignment(.leading)

                ForEach(record.insight.superlatives.prefix(2), id: \.self) { superlative in
                    HStack(spacing: Theme.Spacing.s) {
                        Circle()
                            .fill(Theme.Colors.persona(record.persona))
                            .frame(width: 6, height: 6)
                        Text(superlative.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Text("View full analysis")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Stats Dashboard

    /// 2×2 dashboard summarising key numbers from the latest scan.
    private func quickStatsDashboard(_ stats: PhotoStats) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Quick Stats")
                .font(Theme.Typography.headline)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                          GridItem(.flexible())],
                spacing: Theme.Spacing.m
            ) {
                StatCard(
                    icon: "photo.on.rectangle.angled",
                    value: "\(stats.totalPhotos)",
                    label: "Total Photos",
                    fill: Theme.Colors.cardCycle[0]
                )
                StatCard(
                    icon: "person.crop.circle",
                    value: "\(Int(stats.selfieRatio * 100))%",
                    label: "Selfie Ratio",
                    fill: Theme.Colors.cardCycle[1]
                )
                StatCard(
                    icon: "rectangle.on.rectangle",
                    value: "\(stats.screenshotCount)",
                    label: "Screenshots",
                    fill: Theme.Colors.cardCycle[2]
                )
                StatCard(
                    icon: "heart.fill",
                    value: "\(stats.favoriteCount)",
                    label: "Favorites",
                    fill: Theme.Colors.cardCycle[3]
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(
                systemImage: "photo.stack",
                title: "Nothing roasted yet",
                message: "Run your first analysis and find out what your photo library really says about you."
            )
            .padding(.top, Theme.Spacing.xxl)

            Button("Scan My Gallery") { startScan() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

/// Small persona badge used on cards and rows.
struct PersonaChip: View {
    let persona: Persona

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: persona.symbolName)
                .font(.system(size: 11, weight: .medium))
            Text(persona.displayName.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
        }
        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
        .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(Theme.Colors.persona(persona).opacity(0.5), in: Capsule())
    }
}

/// Single stat tile used in the Quick Stats dashboard on Home.
struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let fill: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(0.5)
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(fill.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
