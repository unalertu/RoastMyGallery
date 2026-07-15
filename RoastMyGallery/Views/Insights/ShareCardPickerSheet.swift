import SwiftUI

/// One rendered card option in the share picker.
struct RenderedShareCard: Identifiable {
    let id: String
    let title: String
    let image: UIImage
}

/// Identifiable wrapper so InsightView can drive `.sheet(item:)`.
struct ShareCardSet: Identifiable {
    let id = UUID()
    let cards: [RenderedShareCard]
}

/// Share preview: swipe (or tap the style chips) between the classic and
/// editorial cards, then share the selected one. Calm pastel modal styling.
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
                            Image(uiImage: card.image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                                .softShadow()
                                .padding(.horizontal, Theme.Spacing.l)
                                .padding(.vertical, Theme.Spacing.s)
                                .tag(card.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(Theme.motion, value: selectedID)

                    stylePicker

                    if let selected {
                        ShareLink(
                            item: Image(uiImage: selected.image),
                            preview: SharePreview("My Gallery, Roasted", image: Image(uiImage: selected.image))
                        ) {
                            Label("Share This Card", systemImage: "square.and.arrow.up")
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
