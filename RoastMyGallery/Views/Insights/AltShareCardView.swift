import SwiftUI

// MARK: - Variants

/// Background treatments for the editorial card. Seeded from the insight ID
/// so a given analysis always renders the same variant, but different
/// analyses rotate — repeat users don't get identical-looking cards.
struct AltCardVariant: Equatable {
    let name: String
    let gradient: [Color]
    let blobA: Color
    let blobB: Color

    static let blush = AltCardVariant(
        name: "blush",
        gradient: [Color(hex: 0xFAF6F0), Color(hex: 0xF2D8CE)],
        blobA: Theme.Colors.sage,
        blobB: Theme.Colors.powderBlue
    )
    static let meadow = AltCardVariant(
        name: "meadow",
        gradient: [Color(hex: 0xFAF6F0), Color(hex: 0xD9E2CF)],
        blobA: Theme.Colors.dustyRose,
        blobB: Theme.Colors.powderBlue
    )
    static let sky = AltCardVariant(
        name: "sky",
        gradient: [Color(hex: 0xFAF6F0), Color(hex: 0xD3E0E9)],
        blobA: Theme.Colors.dustyRose,
        blobB: Theme.Colors.sage
    )

    static let all: [AltCardVariant] = [.blush, .meadow, .sky]

    /// Deterministic pick — stable across launches for the same insight.
    static func seeded(by id: UUID) -> AltCardVariant {
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return all[sum % all.count]
    }
}

// MARK: - Card

/// The second, "editorial" share card — Spotify-Wrapped-meets-soft-minimal.
/// Visually distinct from `ShareCardView` (dark gradient, untouched): light
/// pastel gradient background with soft blobs, a serif hero quote, and
/// designed stat widgets.
///
/// 360×640 logical, rendered @3x = 1080×1920 by `AltShareCardRenderer`.
/// Content keeps ~84pt (≈250px @3x) clear top and bottom, where Stories UI
/// overlays live.
struct AltShareCardView: View {
    let insight: Insight
    let stats: PhotoStats
    let variant: AltCardVariant

    init(insight: Insight, stats: PhotoStats, variant: AltCardVariant? = nil) {
        self.insight = insight
        self.stats = stats
        self.variant = variant ?? .seeded(by: insight.id)
    }

    /// Stories-UI safe zone, top and bottom.
    private let safeZone: CGFloat = 84

    private var heroLine: String {
        insight.shareLine ?? insight.headline
    }

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer(minLength: Theme.Spacing.m)

                hero

                Spacer(minLength: Theme.Spacing.m)

                statsPanel
                    .padding(.bottom, Theme.Spacing.l)

                footer
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, safeZone)
            .padding(.bottom, safeZone)
        }
        .frame(width: 360, height: 640)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(colors: variant.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(variant.blobA.opacity(0.5))
                .frame(width: 240, height: 240)
                .blur(radius: 48)
                .offset(x: -120, y: -200)
            Circle()
                .fill(variant.blobB.opacity(0.45))
                .frame(width: 300, height: 300)
                .blur(radius: 56)
                .offset(x: 150, y: 60)
            Circle()
                .fill(variant.blobA.opacity(0.3))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: -80, y: 280)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: Theme.Spacing.s) {
                logoMark
                Text("ROAST MY GALLERY")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Text(insight.persona == .roast ? "🔥" : "🧠")
                    .font(.system(size: 11))
                Text(insight.persona.displayName.uppercased())
                    .font(Theme.Typography.label)
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
            }
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(.white.opacity(0.55), in: Capsule())
        }
    }

    /// Tiny app-icon mark.
    private var logoMark: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("“")
                .font(.system(size: 56, weight: .black, design: .serif))
                .foregroundStyle(Theme.Colors.accent)
                .frame(height: 30, alignment: .top)

            Text(heroLine)
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(3)
                .minimumScaleFactor(0.55)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Stats widgets

    private var statsPanel: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                SelfieRingWidget(ratio: stats.selfieRatio)
                CategoryBarsWidget(categories: Array(stats.topCategories.prefix(3)))
            }

            if let busiest = busiestMonth {
                MonthCalloutWidget(monthName: busiest.name, count: busiest.count)
            }
        }
        .padding(Theme.Spacing.m)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var busiestMonth: (name: String, count: Int)? {
        guard let best = stats.photosByMonth.max(by: { $0.value < $1.value }) else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM"
        guard let date = parser.date(from: best.key) else { return nil }
        let printer = DateFormatter()
        printer.dateFormat = "LLLL"
        return (printer.string(from: date), best.value)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.s) {
            Spacer()
            logoMark.scaleEffect(0.8)
            Text("Made with Roast My Gallery")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
    }
}

// MARK: - Widgets

/// Donut ring for the selfie ratio — single series, value labeled in the
/// center so color never carries the number alone.
private struct SelfieRingWidget: View {
    let ratio: Double

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.textPrimary.opacity(0.08), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, ratio)))
                    .stroke(Theme.Colors.chartRose, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(ratio * 100))%")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: 88, height: 88)

            Text("selfies")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// Top categories as thin horizontal bars, longest first. Each bar is
/// directly labeled with name + count; hue order is fixed (never cycled).
private struct CategoryBarsWidget: View {
    let categories: [CategoryCount]

    private let maxBarWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + 2) {
            Text("MOST PHOTOGRAPHED")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)

            if categories.isEmpty {
                Text("An eclectic mix — no clear favorite")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(Array(categories.enumerated()), id: \.element) { index, item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.category.capitalized)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: Theme.Spacing.s)
                            Text("\(item.count)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Capsule()
                            .fill(Theme.Colors.chartSeries[index % Theme.Colors.chartSeries.count])
                            .frame(width: barWidth(for: item), height: 9)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barWidth(for item: CategoryCount) -> CGFloat {
        let maxCount = categories.map(\.count).max() ?? 1
        guard maxCount > 0 else { return 12 }
        return max(12, maxBarWidth * CGFloat(item.count) / CGFloat(maxCount))
    }
}

/// "Busiest month" callout pill.
private struct MonthCalloutWidget: View {
    let monthName: String
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.chartBlue)
            Text("Busiest month")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text("\(monthName) · \(count) photos")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(.white.opacity(0.5), in: Capsule())
    }
}
