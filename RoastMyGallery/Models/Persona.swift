import Foundation

/// The narrative voice used when generating insights.
///
/// Persona choice is a stylistic preference, never a paywall lever — both are
/// always available. Monetization is per-action credits (see `PurchaseManager`),
/// not persona gating. There is deliberately no default persona: the picker
/// presents both neutrally and the user must choose.
enum Persona: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Witty, teasing commentary about the user's photo habits.
    case roast

    /// Softer, pseudo-psychological "what your photos say about you" analysis.
    case analyst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .roast: return "Roast"
        case .analyst: return "Analyst"
        }
    }

    var tagline: String {
        switch self {
        case .roast: return "Playfully brutal"
        case .analyst: return "Thoughtfully curious"
        }
    }

    /// Longer copy for the persona picker cards — describes how each tone
    /// *feels*, phrased so neither reads as the premium option.
    var pickerDescription: String {
        switch self {
        case .roast:
            return "A witty friend teasing you about your camera roll. Sharp, but never mean."
        case .analyst:
            return "A gentle, curious read on what your photos say about you."
        }
    }

    var symbolName: String {
        switch self {
        case .roast: return "flame"
        case .analyst: return "brain.head.profile"
        }
    }
}
