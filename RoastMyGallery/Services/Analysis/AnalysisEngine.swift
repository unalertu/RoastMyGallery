import Foundation
import SwiftUI

// MARK: - Pipeline overview
//
// The whole app is this pipeline; each stage is a protocol so any of them can
// be swapped (mocked in previews/tests, or pointed at a real backend later):
//
//   PhotoLibraryService  →  PhotoAnalyzing (on-device Vision)
//                        →  StatsAggregating (observations → PhotoStats JSON)
//                        →  InsightGenerating (stats JSON → LLM narrative)
//                        →  ShareCardRendering (narrative → shareable image)
//
// The hand-picked flow adds a parallel branch: DeepVisionAnalyzing
// (explicit-consent photo upload → per-photo commentary).

/// Progress reporting for the on-device scan. Sent frequently; keep it cheap.
struct AnalysisProgress: Sendable, Equatable {
    let completed: Int
    let total: Int

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Stage 1 output: the observations plus the true number of assets the scope
/// matched, so downstream stats can report "analyzed X of Y" honestly when
/// some assets couldn't be analyzed (thumbnail unavailable, Vision failure).
struct ScanOutput: Sendable {
    /// Every image asset the scope matched in the library.
    let totalAssets: Int
    /// One entry per successfully analyzed asset. Always ≤ `totalAssets`.
    let observations: [PhotoObservation]
}

/// Stage 1 — enumerate the library and run on-device Vision requests.
/// Implementations must never move pixel data off-device.
protocol PhotoAnalyzing: Sendable {
    /// Analyzes all photos within `scope`, invoking `onProgress` as batches
    /// complete. Must be cancellable via structured concurrency and must not
    /// block the main thread.
    func analyze(
        scope: AnalysisScope,
        onProgress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> ScanOutput
}

/// Stage 2 — fold per-photo observations into the compact stats object.
protocol StatsAggregating: Sendable {
    /// - Parameter totalPhotos: the true asset count the scope matched (from
    ///   `ScanOutput.totalAssets`), which may exceed `observations.count`.
    /// - Parameter depth: `.deep` keeps a wider category slice (top 25 vs 10)
    ///   to feed the longer deep-analysis narrative.
    func aggregate(
        _ observations: [PhotoObservation],
        totalPhotos: Int,
        scope: AnalysisScope,
        depth: AnalysisDepth
    ) -> PhotoStats

    /// Category → representative asset local identifiers, for showing a
    /// matching photo next to insight segments. Stays on-device (persisted in
    /// `AnalysisRecord`), never serialized to the backend.
    func photoIndex(for observations: [PhotoObservation]) -> [String: [String]]
}

/// Stage 3 — turn stats into a narrative. The only stage that talks to the
/// network, and it only ever sends the `PhotoStats` JSON (plus the RevenueCat
/// App User ID so the backend can deduct 1 gem *after* a successful
/// generation — never the photos themselves).
protocol InsightGenerating: Sendable {
    /// - Parameter appUserID: RevenueCat App User ID, passed to the backend so
    ///   it can deduct the analysis gem on success. Ignored by offline/mock
    ///   generators (which don't charge).
    /// - Parameter variationSeed: advances each time the *same* stats are
    ///   re-generated (0 for a first analysis, 1 for the first Regenerate, …).
    ///   The backend uses it to rotate the narrative "lens" and spotlight
    ///   different topics so a fresh take actually reads differently.
    /// - Parameter depth: `.deep` asks the backend for the long-form contract
    ///   (12–16 beats, stronger model) and costs 5 gems instead of 1 —
    ///   both enforced server-side.
    /// - Parameter runID: charge-idempotency token. The caller keeps it STABLE
    ///   across retries of the same run (see `ScanViewModel`'s pending run),
    ///   so a retry after a lost response can never be charged twice —
    ///   the backend claims the deduction per (user, runID) atomically.
    func generateInsight(
        from stats: PhotoStats,
        persona: Persona,
        appUserID: String,
        variationSeed: Int,
        depth: AnalysisDepth,
        runID: UUID
    ) async throws -> Insight
}

/// Deep analysis stage 3.5 — short AI captions for the photos the results
/// screen displays. Best-effort: a failure here never sinks the (already
/// charged) deep run, the cards just render without footers.
///
/// PRIVACY: the SECOND of only two code paths that upload image data (the
/// other is `DeepVisionAnalyzing`), and it runs only after the user's
/// explicit, required consent on the deep setup screen. Photos are downscaled
/// first; asset IDs stay on-device (batch order is the only shared reference).
protocol PhotoCaptioning: Sendable {
    /// Maximum photos a single caption batch may contain.
    var maxBatchSize: Int { get }

    /// - Parameter photos: downscaled JPEGs in batch order, each paired with
    ///   the narrative context of the segment it illustrates.
    /// - Returns: one caption per uploaded photo, in the same batch order.
    ///   May be shorter than the input if the backend trims trailing entries.
    func captions(
        for photos: [CaptionPhoto],
        persona: Persona,
        appUserID: String
    ) async throws -> [String]
}

/// One photo in a caption batch: pixels plus the story beat it sits under.
/// `assetID` never leaves the device — the caller uses it to map results back.
struct CaptionPhoto: Sendable {
    let assetID: String
    let jpegData: Data
    /// The segment text this photo illustrates on the results screen.
    let segmentText: String
    /// The segment's category tag, when it has one.
    let category: String?
}

/// Stage 4 — render the insight into a shareable image (Instagram story sized).
@MainActor
protocol ShareCardRendering {
    func renderCard(insight: Insight, stats: PhotoStats) throws -> UIImage
}

/// The hand-picked flow — deep per-photo analysis of an explicitly consented
/// photo batch, one of the two code paths that upload image data (the other is
/// `PhotoCaptioning`, for deep-analysis captions).
protocol DeepVisionAnalyzing: Sendable {
    /// Maximum number of photos a single batch may contain.
    var maxBatchSize: Int { get }

    /// - Parameter photos: already-downscaled JPEG data for each consented
    ///   photo, keyed by local asset ID (the ID is used to map results back
    ///   and is NOT uploaded — only pixel data and the persona leave the
    ///   device).
    /// - Parameter appUserID: RevenueCat App User ID, passed to the backend so
    ///   it can deduct the 5-gem charge *after* a successful batch. Ignored
    ///   by mocks (which don't charge).
    /// - Parameter runID: charge-idempotency token, stable across retries of
    ///   the same batch (see `DeepVisionRunner`) so a lost response can never
    ///   lead to a double deduction.
    /// - Precondition: caller has verified affordability (UX gate) AND
    ///   recorded explicit per-batch consent (see `DeepVisionFlowView`).
    func analyze(
        photos: [(assetID: String, jpegData: Data)],
        persona: Persona,
        appUserID: String,
        runID: UUID
    ) async throws -> DeepVisionResult
}

enum AnalysisError: LocalizedError {
    case photoAccessDenied
    case emptyLibrary
    case cancelled
    /// The backend's authoritative balance check rejected the run (HTTP 402)
    /// — the local balance was stale-high. No gems were taken.
    case insufficientGems
    case backendUnavailable(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "Photo library access was denied. Enable it in Settings to get roasted."
        case .emptyLibrary:
            return "No photos found in the selected time range."
        case .cancelled:
            return "Analysis was cancelled."
        case .insufficientGems:
            return "Not enough gems for this analysis. No gems were taken — top up and try again."
        case .backendUnavailable:
            return "Couldn't reach the insight service. Try again in a bit."
        }
    }
}
