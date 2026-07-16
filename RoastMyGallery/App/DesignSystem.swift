import SwiftUI

/// Central design tokens — every view pulls colors, spacing, radii, type and
/// motion from here. No hardcoded values in views.
///
/// The palette is light-mode only for now; the app forces Light Mode at the
/// root (see RoastMyGalleryApp). A tuned dark variant is a future pass.
enum Theme {

    // MARK: - Colors — "minimal & pastel"

    enum Colors {
        /// Warm cream — every screen's background.
        static let background = Color(hex: 0xFAF6F0)
        /// Card / elevated surface.
        static let surface = Color.white
        /// Muted terracotta — the single accent for primary actions.
        static let accent = Color(hex: 0xC97B63)
        /// Terracotta wash for soft fills, track backgrounds, highlights.
        static let accentSoft = Color(hex: 0xF3DED7)

        static let textPrimary = Color(hex: 0x3A3532)   // soft charcoal
        static let textSecondary = Color(hex: 0x8A817C) // warm grey

        // Supporting pastels for cards and persona identities.
        static let dustyRose = Color(hex: 0xE8C4BC)
        static let sage = Color(hex: 0xC3D1BA)
        static let powderBlue = Color(hex: 0xC0D2DE)
        static let cream = Color(hex: 0xF4EDE3)

        /// Sage wash / deep sage pair — small-text-on-wash version of the
        /// sage family (used by the Hand-Picked chip in History).
        static let sageSoft = Color(hex: 0xE2EBDA)
        static let sageDeep = Color(hex: 0x5E7C49)

        /// Muted brick for errors — visible but not alarming.
        static let danger = Color(hex: 0xB3564F)

        /// Persona identity tints. Equal visual weight — persona choice is a
        /// stylistic preference, never a tier signal.
        static func persona(_ persona: Persona) -> Color {
            switch persona {
            case .roast: return dustyRose
            case .analyst: return powderBlue
            }
        }

        /// Analysis-tier chip identities (History rows). Standard stays
        /// quiet, Deep borrows the accent, Hand-Picked takes the sage family.
        static func kindText(_ kind: AnalysisKind) -> Color {
            switch kind {
            case .standard: return textSecondary
            case .deep: return accent
            case .handPicked: return sageDeep
            }
        }

        static func kindBackground(_ kind: AnalysisKind) -> Color {
            switch kind {
            case .standard: return cream
            case .deep: return accentSoft
            case .handPicked: return sageSoft
            }
        }

        /// Cycling fills for stat/superlative cards.
        static let cardCycle: [Color] = [dustyRose, sage, powderBlue, cream]

        // Deep data-mark steps of the same pastel hue families, for charts on
        // light surfaces (share-card widgets). Validated with the dataviz
        // palette checker: lightness band, chroma floor, CVD separation, and
        // ≥3:1 contrast on cream all pass. Fixed order — never cycle or
        // reassign by rank; every mark also carries a direct label.
        static let chartRose = Color(hex: 0xC96F52)
        static let chartBlue = Color(hex: 0x3D7FB8)
        static let chartSage = Color(hex: 0x6B9C4A)
        static let chartSeries: [Color] = [chartRose, chartBlue, chartSage]
    }

    // MARK: - Spacing scale

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner radii

    enum Radius {
        static let small: CGFloat = 12
        static let button: CGFloat = 16
        static let card: CGFloat = 20
    }

    // MARK: - Typography — rounded system font, soft hierarchy

    enum Typography {
        static let display = Font.system(size: 34, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .light, design: .rounded)
        static let caption = Font.system(size: 13, weight: .regular, design: .rounded)
        /// Small uppercase labels above values.
        static let label = Font.system(size: 12, weight: .medium, design: .rounded)

        static let bodyLineSpacing: CGFloat = 6
    }

    // MARK: - Motion — gentle, never bouncy

    static let motion = Animation.easeInOut(duration: 0.3)
}

// MARK: - Shared modifiers & styles

extension View {
    /// The one shadow in the app: low opacity, soft blur.
    func softShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    /// Standard card container: surface fill, 20pt corners, soft shadow.
    func themedCard(fill: Color = Theme.Colors.surface) -> some View {
        self
            .padding(Theme.Spacing.m)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .softShadow()
    }
}

/// Primary action: terracotta fill, cream text, gentle press feedback.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                Theme.Colors.accent.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: Theme.Radius.button)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.motion, value: configuration.isPressed)
    }
}

/// Secondary action: soft terracotta wash, accent text.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
            .background(Theme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.motion, value: configuration.isPressed)
    }
}

/// Tertiary / quiet action: plain text, secondary color.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.s)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
