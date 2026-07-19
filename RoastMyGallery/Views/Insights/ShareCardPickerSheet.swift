import SwiftUI

/// One rendered card option in the share picker. The single-card styles hold
/// one image; the Full Story option holds one image per panel (shared
/// together as a set).
struct RenderedShareCard: Identifiable {
    let id: String
    let title: String
    let images: [UIImage]

    init(id: String, title: String, image: UIImage) {
        self.init(id: id, title: title, images: [image])
    }

    init(id: String, title: String, images: [UIImage]) {
        self.id = id
        self.title = title
        self.images = images
    }
}

/// Identifiable wrapper so presenters can drive `.sheet(item:)`.
struct ShareCardSet: Identifiable {
    let id = UUID()
    let cards: [RenderedShareCard]
}

extension ShareCardSet {
    /// Renders the full three-style set (classic, editorial, Full Story) for
    /// one record. Shared by every share entry point (InsightView, Home's
    /// latest-roast shortcut) so they always offer the same styles. Only for
    /// stats-based records — Deep Vision records have no card renderer.
    @MainActor
    static func render(for record: AnalysisRecord) async throws -> ShareCardSet {
        let classic = try ShareCardRenderer()
            .renderCard(insight: record.insight, stats: record.stats)
        let editorial = try AltShareCardRenderer()
            .renderCard(insight: record.insight, stats: record.stats)

        // The Full Story set: resolve the same per-segment photos the
        // narrative cards show (async — iCloud originals may need a fetch),
        // then render one 9:16 panel per page.
        let panels = await FullStoryBuilder.panels(for: record)
        let storyImages = try await FullStoryRenderer()
            .render(record: record, panels: panels)

        return ShareCardSet(cards: [
            RenderedShareCard(id: "classic", title: "Classic", image: classic),
            RenderedShareCard(id: "editorial", title: "Editorial", image: editorial),
            RenderedShareCard(id: "fullstory", title: "Full Story", images: storyImages),
        ])
    }
}

/// Share preview: swipe (or tap the style chips) between the classic card,
/// the editorial card, and the Full Story panel set, then share the selected
/// one. Calm pastel modal styling.
struct ShareCardPickerSheet: View {
    let cards: [RenderedShareCard]
    @State private var selectedID: String

    init(cards: [RenderedShareCard]) {
        self.cards = cards
        _selectedID = State(initialValue: cards.first?.id ?? "")
    }

    private var selected: RenderedShareCard? {
        cards.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(spacing: Theme.Spacing.m) {
                    TabView(selection: $selectedID) {
                        ForEach(cards) { card in
                            cardPreview(card)
                                .tag(card.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(Theme.motion, value: selectedID)

                    stylePicker

                    if let selected {
                        if selected.images.count > 1 {
                            Text("Stories takes one panel at a time — save the set to post them in order.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.l)
                        }

                        ShareLink(
                            items: selected.images.map { Image(uiImage: $0) },
                            preview: { SharePreview("My Gallery, Roasted", image: $0) }
                        ) {
                            Label(
                                selected.images.count > 1
                                    ? "Share All \(selected.images.count) Panels"
                                    : "Share This Card",
                                systemImage: "square.and.arrow.up"
                            )
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.bottom, Theme.Spacing.m)
                    }
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .navigationTitle("Your Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        }
        // One place catches both ways of switching styles — chip tap and
        // pager swipe.
        .onChange(of: selectedID) { _, _ in Haptics.selection() }
    }

    /// Single-image cards preview as-is; the Full Story set gets its own inner
    /// pager (with dots) so every panel can be inspected before sharing. The
    /// inner pager claims horizontal swipes over the image — the style chips
    /// below remain the way to switch between card styles there.
    @ViewBuilder
    private func cardPreview(_ card: RenderedShareCard) -> some View {
        if card.images.count > 1 {
            TabView {
                ForEach(Array(card.images.enumerated()), id: \.offset) { _, image in
                    cardImage(image)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        } else if let image = card.images.first {
            cardImage(image)
        }
    }

    private func cardImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .softShadow()
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
    }

    /// Segmented style chips, synced with the swipeable pager.
    private var stylePicker: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(cards) { card in
                let isSelected = card.id == selectedID
                Button {
                    selectedID = card.id
                } label: {
                    Text(card.title)
                        .font(Theme.Typography.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(
                            isSelected ? Theme.Colors.accentSoft : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Theme.motion, value: selectedID)
    }
}
