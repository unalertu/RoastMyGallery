import SwiftUI

// MARK: - Panel model

/// One panel of the "Full Story" share set — the third share format, a
/// sequence of 9:16 story pages covering the ENTIRE analysis: a cover, one
/// page per 1–2 narrative beats (with the beat's photo + AI caption when the
/// results screen shows one), and a closing superlatives page.
///
/// Everything here is fully resolved for synchronous rendering: photos arrive
/// as loaded `UIImage`s because `ImageRenderer` snapshots the view tree in one
/// pass and can't wait on `PHImageManager` (see `FullStoryBuilder`).
enum FullStoryPanel {
    case cover
    case beats([ResolvedBeat])
    /// `hiddenBeatCount` > 0 when a very long deep story was truncated to
    /// `FullStoryBuilder.maxBeatPanels` pages — the closing panel says so.
    case closing(hiddenBeatCount: Int)

    /// A narrative beat with its display photo already loaded (or none —
    /// text-only beats and failed loads render without one, same contract as
    /// `InsightSegmentCard`).
    struct ResolvedBeat: Identifiable {
        let id = UUID()
        let text: String
        let photo: UIImage?
        /// Deep analysis only: the AI caption for `photo`.
        let caption: String?
    }
}

// MARK: - Panel view

/// Renders one Full Story panel at 360×640 logical (1080×1920 @3x, done by
/// `FullStoryRenderer`). Shares the editorial card's seeded pastel language
/// (`AltCardVariant`) so all panels of one story — and the story vs. the
/// editorial card — feel like one family, but the structure is narrative
/// (keepsake of the whole analysis), not a stat teaser.
///
/// Content keeps ~84pt (≈250px @3x) clear top and bottom for Stories UI.
struct FullStoryPanelView: View {
    let record: AnalysisRecord
    let panel: FullStoryPanel
    /// 1-based position in the set, shown in the header ("2/7").
    let index: Int
    let total: Int
    let variant: AltCardVariant

    /// Stories-UI safe zone, top and bottom.
    private let safeZone: CGFloat = 84

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                header

                Spacer(minLength: Theme.Spacing.m)

                content

                Spacer(minLength: Theme.Spacing.m)

                footer
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, safeZone)
            .padding(.bottom, safeZone)
        }
        .frame(width: 360, height: 640)
    }

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .cover:
            cover
        case .beats(let beats):
            beatStack(beats)
        case .closing(let hiddenBeatCount):
            closing(hiddenBeatCount: hiddenBeatCount)
        }
    }

    // MARK: Background — same recipe as the editorial card, softer blobs so
    // beat text and photos stay the loudest thing on the page.

    private var background: some View {
        ZStack {
            LinearGradient(colors: variant.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(variant.blobA.opacity(0.4))
                .frame(width: 260, height: 260)
                .blur(radius: 52)
                .offset(x: -130, y: -220)
            Circle()
                .fill(variant.blobB.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 56)
                .offset(x: 160, y: 240)
        }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack {
            HStack(spacing: Theme.Spacing.s) {
                logoMark
                Text("THE FULL STORY")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text("\(index)/\(total)")
                .font(Theme.Typography.label)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
                .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(.white.opacity(0.55), in: Capsule())
        }
    }

    /// Tiny three-dot mark echoing the app icon (same as the editorial card).
    private var logoMark: some View {
        HStack(spacing: 3) {
            Circle().fill(Theme.Colors.accent).frame(width: 7, height: 7)
            Circle().fill(Theme.Colors.sage).frame(width: 7, height: 7)
            Circle().fill(Theme.Colors.powderBlue).frame(width: 7, height: 7)
        }
    }

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

    // MARK: Cover

    private var cover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                personaChip
                if record.depth == .deep {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                        Text("DEEP ANALYSIS")
                            .font(Theme.Typography.label)
                            .tracking(1)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(.white.opacity(0.55), in: Capsule())
                }
            }

            Text(record.insight.headline)
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(3)
                .minimumScaleFactor(0.5)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(record.stats.scope.displayLabel, systemImage: "calendar")
                Label("\(record.stats.analyzedPhotos) photos analyzed", systemImage: "photo.on.rectangle")
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.xs) {
                Text("swipe for the story")
                    .font(Theme.Typography.caption)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.Colors.textPrimary.opacity(0.6))
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var personaChip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(record.persona == .roast ? "🔥" : "🧠")
                .font(.system(size: 11))
            Text(record.persona.displayName.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.7))
        }
        .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(.white.opacity(0.55), in: Capsule())
    }

    // MARK: Beats

    private func beatStack(_ beats: [FullStoryPanel.ResolvedBeat]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(beats) { beat in
                beatCard(beat, isAlone: beats.count == 1)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func beatCard(_ beat: FullStoryPanel.ResolvedBeat, isAlone: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s + Theme.Spacing.xs) {
            Text(beat.text)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(4)
                // A photo beat owns its panel and shares it with the image;
                // paired text-only beats each get roughly half the page.
                .lineLimit(isAlone ? (beat.photo == nil ? 16 : 8) : 9)
                .minimumScaleFactor(0.7)

            if let photo = beat.photo {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 218)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))

                if let caption = beat.caption {
                    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.top, 2)
                        Text(caption)
                            .font(Theme.Typography.caption)
                            .italic()
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: Closing

    private func closing(hiddenBeatCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("THE SUPERLATIVES")
                .font(Theme.Typography.label)
                .tracking(2)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ForEach(Array(record.insight.superlatives.prefix(4).enumerated()), id: \.offset) { _, superlative in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(superlative.title.uppercased())
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(superlative.detail)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Radius.card))

            if hiddenBeatCount > 0 {
                Label(
                    "+\(hiddenBeatCount) more \(hiddenBeatCount == 1 ? "beat" : "beats") in the app",
                    systemImage: "ellipsis.circle"
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Text("What does your gallery say about you?")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineSpacing(2)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
