import SwiftUI

/// The "New Analysis" options sheet: choose between the standard 1-credit
/// analysis and the 5-credit Deep Analysis, with the hand-picked Deep Vision
/// batch as a discoverable third entry below the two main cards.
///
/// Pure chooser — it only reports the choice; the presenter (HomeView) routes
/// into the right flow after the sheet dismisses.
struct AnalysisTypeSheet: View {
    enum Choice {
        /// The classic 1-credit stats analysis.
        case standard
        /// The 5-credit date-range deep analysis.
        case deep
        /// The 5-credit hand-picked ≤30 photo Deep Vision batch.
        case handPicked
    }

    @Environment(\.dismiss) private var dismiss
    let onSelect: (Choice) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.l) {
                        VStack(spacing: Theme.Spacing.s) {
                            Text("How deep should we go?")
                                .font(Theme.Typography.title)
                            Text("Pick the kind of analysis you want.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Spacing.l)

                        optionCard(
                            title: "Standard",
                            cost: "1 credit",
                            systemImage: "wand.and.stars",
                            highlights: [
                                "Your story in 5–7 sharp beats",
                                "Top 10 subjects and habits",
                                "Any scope: all time, a month, an album",
                            ],
                            footnote: "Ready in seconds"
                        ) {
                            select(.standard)
                        }

                        optionCard(
                            title: "Deep Analysis",
                            cost: "5 credits",
                            systemImage: "sparkles",
                            highlights: [
                                "A 2–3× longer, richer story",
                                "25+ categories, month-by-month arcs",
                                "An AI caption under every photo card",
                                "Any date range up to 1 year",
                            ],
                            footnote: "Takes a few minutes"
                        ) {
                            select(.deep)
                        }

                        handPickedRow
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private func select(_ choice: Choice) {
        onSelect(choice)
        dismiss()
    }

    private func optionCard(
        title: String,
        cost: String,
        systemImage: String,
        highlights: [String],
        footnote: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(Theme.Typography.headline)
                    Spacer()
                    Text(cost)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.accentSoft, in: Capsule())
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(highlights, id: \.self) { highlight in
                        HStack(alignment: .top, spacing: Theme.Spacing.s) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(.top, 3)
                            Text(highlight)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }

                Text(footnote)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    /// Deliberately quieter than the two cards above: a discoverable extra,
    /// not a competing third tier.
    private var handPickedRow: some View {
        Button {
            select(.handPicked)
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("Hand-Picked")
                            .font(Theme.Typography.headline)
                        Spacer()
                        Text("5 credits")
                            .font(Theme.Typography.label)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text("You pick up to 30 photos yourself; the AI reads each one up close — no scan, no date range.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}
