import Foundation

/// How much a single analysis run digs in. Chosen on the "New Analysis"
/// options sheet and threaded through the whole pipeline — the depth changes
/// how many categories `StatsAggregator` keeps, which model/output contract
/// the backend uses, whether per-photo captions are generated, and what the
/// run costs (see `PurchaseManager`).
enum AnalysisDepth: String, Codable, Sendable, Hashable {
    /// The classic 1-credit analysis: 5–7 narrative beats, top 10 categories.
    case standard
    /// The 5-credit deep analysis: a date range of up to one year, a much
    /// longer story (12–16 beats), top 25 categories, and an AI caption under
    /// every photo shown in the results.
    case deep
}
