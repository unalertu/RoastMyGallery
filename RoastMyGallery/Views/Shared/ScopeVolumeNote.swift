import SwiftUI

/// Live "how much is actually in here" line for the scope pickers.
///
/// WHY THIS EXISTS: the backend prompt writes a fixed number of beats no matter
/// how little data arrives, so a near-empty month doesn't produce a short
/// story — it produces a padded one. The scan itself is happy to run and the
/// gem is charged on success, so a user can pay for filler without ever being
/// told the month was thin. The honest place to say so is here, while the
/// choice is still free to change.
///
/// Deliberately does NOT block: someone may genuinely want their 9-photo
/// holiday album read. It sets the expectation and gets out of the way — only
/// a truly empty scope disables the confirm button, because that run can't
/// produce anything at all.
struct ScopeVolumeNote: View {
    let count: Int
    let depth: AnalysisDepth
    /// What the count refers to, e.g. "April 2026" — named so the warning
    /// can't be mistaken for a statement about the whole library.
    let scopeLabel: String

    private var sufficiency: AnalysisDepth.Sufficiency {
        depth.sufficiency(forPhotoCount: count)
    }

    var body: some View {
        Label(message, systemImage: icon)
            .font(Theme.Typography.caption)
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
    }

    private var message: String {
        switch sufficiency {
        case .empty:
            return "No photos in \(scopeLabel)"
        case .thin:
            return "Only \(formattedCount) \(count == 1 ? "photo" : "photos") in \(scopeLabel) — the story will be short. A fuller \(depth == .deep ? "range" : "month") gives a richer read."
        case .good:
            return "\(formattedCount) photos in \(scopeLabel)"
        }
    }

    private var icon: String {
        switch sufficiency {
        case .empty: return "exclamationmark.triangle"
        case .thin: return "info.circle"
        case .good: return "photo.on.rectangle.angled"
        }
    }

    private var tint: Color {
        switch sufficiency {
        case .empty: return Theme.Colors.danger
        case .thin: return Theme.Colors.accent
        case .good: return Theme.Colors.textSecondary
        }
    }

    private var formattedCount: String {
        count.formatted(.number.grouping(.automatic))
    }
}

/// Counts photos for a scope off the main thread, debounced against a rapidly
/// changing selection (a spinning picker wheel emits many values). Owned by
/// the picker sheets; `count` is nil until the first result lands, so nothing
/// flashes a misleading zero.
@MainActor
@Observable
final class ScopeVolumeCounter {
    private(set) var count: Int?

    private let countPhotos: @Sendable (AnalysisScope) -> Int
    private var task: Task<Void, Never>?

    init(countPhotos: @escaping @Sendable (AnalysisScope) -> Int) {
        self.countPhotos = countPhotos
    }

    /// Recount for a new scope. Cancels any in-flight count, so only the
    /// wheel's final resting position costs a PhotoKit query.
    func update(for scope: AnalysisScope) {
        task?.cancel()
        let countPhotos = self.countPhotos
        task = Task { [weak self] in
            // Settle time: a wheel drag emits a value per detent.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { countPhotos(scope) }.value
            guard !Task.isCancelled else { return }
            self?.count = result
        }
    }
}
