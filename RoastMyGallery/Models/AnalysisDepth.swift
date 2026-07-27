import Foundation

/// How much a single analysis run digs in. Chosen on Home's "New Analysis"
/// product cards and threaded through the whole pipeline — the depth changes
/// how many categories `StatsAggregator` keeps, which model/output contract
/// the backend uses, whether per-photo captions are generated, and what the
/// run costs (see `PurchaseManager`).
enum AnalysisDepth: String, Codable, Sendable, Hashable {
    /// The classic 1-gem analysis: 5–7 narrative beats, top 10 categories.
    case standard
    /// The 5-gem deep analysis: a date range of up to one year, a much
    /// longer story (12–16 beats), top 25 categories, and an AI caption under
    /// every photo shown in the results.
    case deep
}

// MARK: - How much material a run needs

extension AnalysisDepth {
    /// Whether the chosen scope holds enough photos for a story worth a gem.
    ///
    /// The backend prompt asks for a fixed number of beats regardless of how
    /// much data arrives ("even for a small library, write the full 5-7
    /// beats"), so a nearly-empty scope doesn't produce a short story — it
    /// produces a padded one, which reads as filler and is the fastest way to
    /// lose someone on the first thing they spent a gem on. The scan itself is
    /// happy to run, so the honest place to intervene is the picker, before
    /// anyone pays.
    enum Sufficiency {
        /// Nothing to analyze — the run would fail with `emptyLibrary`.
        case empty
        /// Enough to run, but the story will be thin and repetitive.
        case thin
        /// Enough material for the beat count this depth writes.
        case good
    }

    /// Below this a scope can't fill this depth's beat count without padding.
    /// Deep asks for 12–16 beats across at least 8 categories, so it needs
    /// substantially more material than standard's 5–7.
    var thinPhotoThreshold: Int {
        switch self {
        case .standard: return 25
        case .deep: return 120
        }
    }

    func sufficiency(forPhotoCount count: Int) -> Sufficiency {
        if count == 0 { return .empty }
        return count < thinPhotoThreshold ? .thin : .good
    }
}
