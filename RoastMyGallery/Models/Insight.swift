import Foundation

/// The LLM-generated narrative for one analysis run. This is what the results
/// screen displays and what `ShareCardRenderer` turns into a shareable image.
struct Insight: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    let persona: Persona
    let generatedAt: Date

    /// Short punchy title for the share card, e.g. "Certified Food Paparazzo".
    let headline: String

    /// The main narrative (a few paragraphs in the persona's voice).
    /// Always kept in sync with `segments` (joined texts) so the share card
    /// and older render paths never depend on segments existing.
    let body: String

    /// The narrative split into beats, each optionally tagged with a category
    /// from the user's own stats so the results screen can show a matching
    /// photo (via `AnalysisRecord.categoryPhotoIndex` — on-device only).
    /// Optional: older persisted records and older backends predate it, and
    /// the backend serves nil when the model ignores the segmented contract.
    var segments: [Segment]?

    /// One quotable one-liner — the hero of the editorial share card.
    /// Optional because older persisted records and older backend responses
    /// predate it; consumers fall back to `headline`.
    var shareLine: String?

    /// Bite-sized stats/awards rendered as card line items,
    /// e.g. ("Selfie ratio", "31% — the front camera is tired").
    let superlatives: [Superlative]

    struct Superlative: Codable, Sendable, Hashable {
        let title: String
        let detail: String
    }

    /// One narrative beat. `category` is a value from the user's detected
    /// categories (or nil for general commentary) — the backend only ever tags
    /// categories that appear in the submitted `PhotoStats`.
    struct Segment: Codable, Sendable, Hashable {
        let text: String
        let category: String?
    }
}

/// The output of one hand-picked Deep Vision batch — an overall summary line
/// plus photo-level commentary segments. Persisted inside the run's
/// `AnalysisRecord` (device-only, like everything else in history).
struct DeepVisionResult: Codable, Sendable, Hashable {
    /// One overall observation about the whole batch.
    let summary: String
    let segments: [Segment]

    /// One commentary beat about specific photo(s) in the batch.
    struct Segment: Codable, Sendable, Hashable, Identifiable {
        var id: UUID
        /// Local asset identifiers of the photo(s) this segment is about.
        /// Mapped client-side from the backend's batch indexes — asset IDs are
        /// never uploaded. Empty when the mapping didn't resolve (the segment
        /// still renders as a text-only card).
        let assetIDs: [String]
        let text: String
    }
}
