import Foundation

/// The compact, aggregated statistics object produced by `StatsAggregator`.
///
/// PRIVACY CONTRACT: this is the ONLY thing that ever leaves the device in the
/// free tier (as JSON, to the insight backend). It must never contain image
/// data, asset identifiers, exact coordinates, or any other PII. Keep every
/// field aggregate-level.
struct PhotoStats: Codable, Sendable, Hashable {
    var generatedAt: Date
    var scope: AnalysisScope

    /// Total assets matched by the scope (before sampling/batching limits).
    var totalPhotos: Int
    /// How many were actually run through Vision.
    var analyzedPhotos: Int

    var selfieCount: Int
    var screenshotCount: Int
    var favoriteCount: Int

    /// "0 faces" / "1 face" / "2+ faces" → photo count. String keys keep the
    /// JSON self-describing for the LLM prompt.
    var faceCountBuckets: [String: Int]

    /// Overall top scene/object categories, sorted descending by count.
    var topCategories: [CategoryCount]

    /// Category counts per month, keyed "yyyy-MM" — lets the LLM comment on
    /// trends ("your gym phase died in March").
    var categoriesByMonth: [String: [CategoryCount]]

    /// Photo counts per month, keyed "yyyy-MM".
    var photosByMonth: [String: Int]

    /// 24 buckets, index = hour of day. Fuels "3 AM screenshot goblin" jokes.
    var photosByHourOfDay: [Int]

    /// Top coarse location clusters (no names resolved on purpose — the LLM
    /// only sees relative distribution, e.g. "87% of photos in one area").
    var topLocationClusters: [LocationClusterStat]

    /// Animal label → count, e.g. ["cat": 214].
    var animalCounts: [String: Int]

    var selfieRatio: Double {
        analyzedPhotos > 0 ? Double(selfieCount) / Double(analyzedPhotos) : 0
    }

    /// Empty stats for a run that never scanned the library — the standalone
    /// Hand-Picked flow, whose insight comes entirely from the uploaded photo
    /// batch (Deep Vision), not from aggregate stats. Only `scope` is
    /// meaningful (it labels the entry in History); every count is zero.
    static func handPickedPlaceholder() -> PhotoStats {
        PhotoStats(
            generatedAt: .now,
            scope: .album(identifier: "hand-picked", name: "Hand-picked photos"),
            totalPhotos: 0,
            analyzedPhotos: 0,
            selfieCount: 0,
            screenshotCount: 0,
            favoriteCount: 0,
            faceCountBuckets: ["0": 0, "1": 0, "2+": 0],
            topCategories: [],
            categoriesByMonth: [:],
            photosByMonth: [:],
            photosByHourOfDay: [Int](repeating: 0, count: 24),
            topLocationClusters: [],
            animalCounts: [:]
        )
    }
}

struct CategoryCount: Codable, Sendable, Hashable {
    let category: String
    let count: Int
}

/// Aggregate share of photos taken within one coarse grid cell.
/// Coordinates are already rounded (see `CoarseLocation`); we additionally
/// only serialize the *share*, not the cell itself, when sent to the backend.
struct LocationClusterStat: Codable, Sendable, Hashable {
    /// Fraction of located photos falling in this cluster, 0...1.
    let share: Double
    /// Rank label like "cluster-1" — deliberately not a place name.
    let label: String
}
