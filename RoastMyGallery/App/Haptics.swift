import UIKit

/// Central haptic vocabulary — every view calls these instead of creating its
/// own generators, so interactions of the same weight always feel the same:
///
/// - `tap` — light impact for minor taps: chips, shortcuts, minimize/cancel.
/// - `primary` — medium impact for actions that commit something: starting a
///   run, buying a pack, regenerating.
/// - `selection` — choosing among options: persona cards, filters, card styles.
/// - `success` / `warning` / `error` — outcome notifications: results ready,
///   routed to the paywall, run failed.
///
/// Generators are created per call: these fire on sparse UI events (not in
/// tight loops), and a fresh generator avoids keeping the Taptic Engine
/// primed for no reason.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func primary() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
