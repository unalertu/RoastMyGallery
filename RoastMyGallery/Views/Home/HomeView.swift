import SwiftUI

/// Tab 1 — the app's entry point, action-first: the three analysis flows are
/// always visible as product cards up top (no chooser sheet), followed by the
/// latest roast (with a share shortcut), a rotating fun-fact teaser drawn from
/// the last scan's stats, and a strip of earlier analyses bridging to History.
struct HomeView: View {
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(DeepVisionRunner.self) private var deepVisionRunner
    @Environment(PurchaseManager.self) private var purchaseManager

    @Binding var selectedTab: AppTab

    @State private var showPaywall = false
    @State private var shareCardSet: ShareCardSet?
    @State private var isPreparingShareCards = false
    @State private var shareErrorMessage: String?
    @State private var teaserFact: TeaserFact?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header

                        if let latest = history.latest {
                            analysisMenu

                            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                                Text("Latest Analysis")
                                    .font(Theme.Typography.headline)
                                latestCard(latest)
                            }

                            if let fact = teaserFact {
                                teaserCard(fact)
                            }

                            statsSnapshot

                            earlierStrip
                        } else {
                            emptyIntro

                            analysisMenu
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $shareCardSet) { set in
            ShareCardPickerSheet(cards: set.cards)
        }
        .alert("Share card failed", isPresented: .init(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .onAppear { teaserFact = teaserFacts.randomElement() }
        // A run finishing while Home is on screen won't refire onAppear, so
        // refresh the teaser when a new record lands.
        .onChange(of: history.records.first?.id) {
            teaserFact = teaserFacts.randomElement()
        }
    }

    /// Routes a product card tap into its flow — unless a run is already
    /// working, in which case reopen it (starting fresh mid-run is how you'd
    /// pay twice).
    private func start(_ kind: AnalysisKind) {
        // Backstop: `analysisMenu` only ever renders launchable kinds, so this
        // can't be reached from the UI — it keeps the invariant local to the
        // one function that acts on it.
        guard AnalysisKind.launchable.contains(kind) else { return }
        Haptics.primary()
        if scanViewModel.isRunActive {
            scanViewModel.presentFlow()
            return
        }
        if deepVisionRunner.isRunActive {
            deepVisionRunner.presentFlow()
            return
        }
        // Both flows are presented by `RootView` off their models' shared
        // `isFlowPresented`, so the banner and notifications can reopen them
        // from any tab — Home only flips the flags.
        switch kind {
        case .standard:
            scanViewModel.prepareForNewScan(depth: .standard)
            scanViewModel.presentFlow()
        case .deep:
            scanViewModel.prepareForNewScan(depth: .deep)
            scanViewModel.presentFlow()
        case .handPicked:
            // Standalone entry: no persona/stats yet — the flow asks first.
            deepVisionRunner.beginFlow()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Roast My Gallery")
                        .font(Theme.Typography.display)
                    Text(history.latest.map { "Last analyzed \($0.createdAt.formatted(.relative(presentation: .named)))" }
                         ?? "Your camera roll has opinions about you")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer(minLength: Theme.Spacing.m)
            gemPill
        }
        .padding(.top, Theme.Spacing.l)
    }

    /// Compact, always-visible gem balance. Tapping opens the gem store.
    private var gemPill: some View {
        Button {
            Haptics.tap()
            showPaywall = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("\(purchaseManager.gemBalance)")
                    .font(Theme.Typography.headline)
            }
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(purchaseManager.gemBalance) gems. Tap to get more.")
    }

    // MARK: - Analysis menu

    /// The three flows as always-visible product cards — the page's primary
    /// action, so it sits right under the header instead of behind a sheet.
    private var analysisMenu: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("New Analysis")
                .font(Theme.Typography.headline)

            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(AnalysisKind.launchable) { kind in
                        productCard(kind)
                    }
                }
                // Bleed to the screen edges while cards still align with the
                // page margin; vertical breathing room keeps shadows unclipped.
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Theme.Spacing.l)
        }
    }

    private func productCard(_ kind: AnalysisKind) -> some View {
        Button { start(kind) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.kindBackground(kind))
                            .frame(width: 40, height: 40)
                        Image(systemName: kind.symbolName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Colors.kindText(kind))
                    }
                    Spacer()
                    costChip(Self.cost(for: kind))
                }

                Text(kind.displayName)
                    .font(Theme.Typography.headline)

                Text(Self.pitch(for: kind))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)

                HStack(spacing: Theme.Spacing.xs) {
                    Text("Start")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Colors.accent)
            }
            .frame(width: 210, alignment: .leading)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    /// Gem price in the same visual language as the balance pill.
    private func costChip(_ cost: Int) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 9, weight: .medium))
            Text("\(cost)")
                .font(Theme.Typography.label)
        }
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.accentSoft, in: Capsule())
    }

    private static func cost(for kind: AnalysisKind) -> Int {
        switch kind {
        case .standard: return PurchaseManager.analysisCost
        case .deep: return PurchaseManager.deepAnalysisCost
        case .handPicked: return PurchaseManager.deepVisionCost
        }
    }

    private static func pitch(for kind: AnalysisKind) -> String {
        switch kind {
        case .standard:
            return "Your story in 5–7 sharp beats. Ready in seconds."
        case .deep:
            // Kept in step with the paywall's Deep row: captions are opt-in,
            // limited to the photos the results show, and user-approved.
            return "A 2–3× richer story over any date range. Optional AI captions on the photos in your results — you approve them first."
        case .handPicked:
            return "You pick up to 30 photos; the AI reads each one up close."
        }
    }

    // MARK: - Latest roast

    /// Compact summary of the most recent analysis; tapping opens the full
    /// results, and the share shortcut renders the share-card set right from
    /// Home. Deliberately slim — superlatives and the long story live in the
    /// full view, so this card doesn't compete with the product cards above.
    private func latestCard(_ record: AnalysisRecord) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            NavigationLink(value: record) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
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
                        .lineLimit(2)

                    // Which slice of the library this story is about (e.g.
                    // "April 2024") — the created date sits in the row above.
                    Label(record.stats.scope.displayLabel, systemImage: "calendar")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                NavigationLink(value: record) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("View full analysis")
                        Image(systemName: "arrow.right")
                    }
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                // Deep Vision records have no share-card renderer, so the
                // shortcut only appears on stats-based roasts.
                if record.deepVision == nil {
                    shareShortcut(record)
                }
            }
        }
        .themedCard()
    }

    private func shareShortcut(_ record: AnalysisRecord) -> some View {
        Button {
            Haptics.tap()
            renderShareCards(for: record)
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                if isPreparingShareCards {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Colors.accent)
                    Text("Preparing…")
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                    Text("Share")
                }
            }
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Colors.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreparingShareCards)
    }

    private func renderShareCards(for record: AnalysisRecord) {
        // Share cards are unlimited in the gem model — no gating here.
        guard !isPreparingShareCards else { return }
        isPreparingShareCards = true
        Task { @MainActor in
            defer { isPreparingShareCards = false }
            do {
                shareCardSet = try await ShareCardSet.render(for: record)
            } catch {
                shareErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Teaser

    /// One rotating fun fact from the latest scan's stats — a fresh pick on
    /// every appearance, with a shuffle button for another.
    private func teaserCard(_ fact: TeaserFact) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: fact.symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(teaserTitle)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(fact.text)
                    .font(Theme.Typography.body)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Theme.Spacing.s)

            if teaserFacts.count > 1 {
                Button {
                    Haptics.tap()
                    withAnimation(Theme.motion) { shuffleTeaser() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show another fact")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(fill: Theme.Colors.cream)
    }

    /// Stats behind the teaser: the newest record that actually scanned the
    /// library — the store's shared rule, so Home, Gallery Stats, and Data
    /// Transparency always agree on which scan is "latest".
    private var teaserSourceStats: PhotoStats? {
        history.latestScanStats
    }

    /// Facts come from one scoped scan, not the whole library — say which
    /// slice ("FROM APRIL 2024"), or the generic line for full-history scans.
    private var teaserTitle: String {
        guard let scope = teaserSourceStats?.scope, scope != .fullHistory else {
            return "FROM YOUR LIBRARY"
        }
        return "FROM \(scope.displayLabel.uppercased())"
    }

    /// Candidate facts drawn from `teaserSourceStats`.
    private var teaserFacts: [TeaserFact] {
        guard let stats = teaserSourceStats else { return [] }

        var facts: [TeaserFact] = []

        if let (animal, count) = stats.animalCounts.max(by: { $0.value < $1.value }), count > 0 {
            facts.append(TeaserFact(
                symbol: "pawprint.fill",
                text: "\(count) \(animal) photos live in your library."
            ))
        }

        let lateNight = stats.photosByHourOfDay.prefix(5).reduce(0, +)
        if lateNight > 0 {
            facts.append(TeaserFact(
                symbol: "moon.stars.fill",
                text: "\(lateNight) photos were taken between midnight and 5 AM."
            ))
        }

        if stats.screenshotCount > 0 {
            facts.append(TeaserFact(
                symbol: "rectangle.on.rectangle",
                text: "\(stats.screenshotCount) screenshots and counting."
            ))
        }

        if let top = stats.topCategories.first {
            facts.append(TeaserFact(
                symbol: "tag",
                text: "Your #1 subject: \(top.category), \(top.count) photos."
            ))
        }

        if let (month, count) = stats.photosByMonth.max(by: { $0.value < $1.value }),
           let label = Self.monthLabel(month) {
            facts.append(TeaserFact(
                symbol: "calendar",
                text: "Your busiest month was \(label) — \(count) photos."
            ))
        }

        // A selfie share only reads sane on a real sample: a tiny scan — or a
        // scan of the Selfies album itself — hits 100%, which is technically
        // true but looks broken on a card.
        if stats.selfieCount > 0, stats.analyzedPhotos >= 20, stats.selfieRatio <= 0.9 {
            facts.append(TeaserFact(
                symbol: "person.crop.circle",
                text: "\(Int(stats.selfieRatio * 100))% of the photos we analyzed are selfies."
            ))
        }

        return facts
    }

    private func shuffleTeaser() {
        let facts = teaserFacts
        guard let current = teaserFact, facts.count > 1 else {
            teaserFact = teaserFacts.randomElement()
            return
        }
        teaserFact = facts.filter { $0 != current }.randomElement()
    }

    /// "2026-03" → "March 2026".
    private static func monthLabel(_ key: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: key) else { return nil }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Stats snapshot

    /// Three key numbers from the latest real scan as tinted tiles — the same
    /// pastel language as the full Gallery Stats dashboard, which "See all"
    /// pushes right from Home's stack.
    @ViewBuilder
    private var statsSnapshot: some View {
        if let stats = teaserSourceStats {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("Gallery Stats")
                        .font(Theme.Typography.headline)
                    Spacer()
                    NavigationLink {
                        GalleryStatsView()
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("See all")
                            Image(systemName: "arrow.right")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: Theme.Spacing.m) {
                    snapshotTile(
                        icon: "photo.on.rectangle.angled",
                        value: "\(stats.analyzedPhotos)",
                        label: "Analyzed",
                        fill: Theme.Colors.dustyRose
                    )
                    // Count, not percentage: a scoped scan (one month, one
                    // album) can legitimately hit 100%, and "100% selfies"
                    // reads as a claim about the whole library.
                    snapshotTile(
                        icon: "person.crop.circle",
                        value: "\(stats.selfieCount)",
                        label: "Selfies",
                        fill: Theme.Colors.powderBlue
                    )
                    snapshotTile(
                        icon: "rectangle.on.rectangle",
                        value: "\(stats.screenshotCount)",
                        label: "Screenshots",
                        fill: Theme.Colors.sage
                    )
                }
            }
        }
    }

    private func snapshotTile(
        icon: String,
        value: String,
        label: String,
        fill: Color
    ) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.m)
        .background(fill.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .softShadow()
    }

    // MARK: - Earlier strip

    /// Everything before the latest record, newest first — the store keeps
    /// records newest-first, so this is a straight dropFirst.
    private var earlierRecords: [AnalysisRecord] {
        Array(history.records.dropFirst().prefix(5))
    }

    @ViewBuilder
    private var earlierStrip: some View {
        if !earlierRecords.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("Earlier Analysis")
                        .font(Theme.Typography.headline)
                    Spacer()
                    Button("See all") { selectedTab = .history }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                        .buttonStyle(.plain)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.m) {
                        ForEach(earlierRecords, id: \.id) { record in
                            earlierCard(record)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -Theme.Spacing.l)
            }
        }
    }

    private func earlierCard(_ record: AnalysisRecord) -> some View {
        NavigationLink(value: record) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Theme.Colors.persona(record.persona))
                            .frame(width: 28, height: 28)
                        Image(systemName: record.persona.symbolName)
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text(record.insight.headline)
                    .font(Theme.Typography.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)

                Text(record.stats.scope.displayLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    /// First-run welcome: deliberately compact — two lines, not a full-screen
    /// illustration — so the product cards stay above the fold, where the
    /// actual first action lives.
    private var emptyIntro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Nothing roasted yet")
                .font(Theme.Typography.title)
            Text("Pick an analysis below and find out what your photo library really says about you.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .padding(.top, Theme.Spacing.m)
    }
}

/// One rotating stat teaser shown on Home.
private struct TeaserFact: Equatable {
    let symbol: String
    let text: String
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
