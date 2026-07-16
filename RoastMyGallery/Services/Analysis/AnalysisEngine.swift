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
// Pro tier adds a parallel branch: DeepVisionAnalyzing (explicit-consent
// photo upload → per-photo commentary).

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
    func aggregate(_ observations: [PhotoObservation], totalPhotos: Int, scope: AnalysisScope) -> PhotoStats

    /// Category → representative asset local identifiers, for showing a
    /// matching photo next to insight segments. Stays on-device (persisted in
    /// `AnalysisRecord`), never serialized to the backend.
    func photoIndex(for observations: [PhotoObservation]) -> [String: [String]]
}

/// Stage 3 — turn stats into a narrative. The only stage that talks to the
/// network, and it only ever sends the `PhotoStats` JSON (plus the RevenueCat
/// App User ID so the backend can deduct 1 credit *after* a successful
/// generation — never the photos themselves).
protocol InsightGenerating: Sendable {
    /// - Parameter appUserID: RevenueCat App User ID, passed to the backend so
    ///   it can deduct the analysis credit on success. Ignored by offline/mock
    ///   generators (which don't charge).
    /// - Parameter variationSeed: advances each time the *same* stats are
    ///   re-generated (0 for a first analysis, 1 for the first Regenerate, …).
    ///   The backend uses it to rotate the narrative "lens" and spotlight
    ///   different topics so a fresh take actually reads differently.
    func generateInsight(
        from stats: PhotoStats,
        persona: Persona,
        appUserID: String,
        variationSeed: Int
    ) async throws -> Insight
}

/// Stage 4 — render the insight into a shareable image (Instagram story sized).
@MainActor
protocol ShareCardRendering {
    func renderCard(insight: Insight, stats: PhotoStats) throws -> UIImage
}

/// Pro tier — deep per-photo analysis of an explicitly consented photo batch.
/// The ONLY code path in the app that uploads image data.
protocol DeepVisionAnalyzing: Sendable {
    /// Maximum number of photos a single batch may contain.
    var maxBatchSize: Int { get }

    /// - Parameter photos: already-downscaled JPEG data for each consented
    ///   photo, keyed by local asset ID (the ID is used to map results back
    ///   and is NOT uploaded — only pixel data and the persona leave the
    ///   device).
    /// - Parameter appUserID: RevenueCat App User ID, passed to the backend so
    ///   it can deduct the 5-credit charge *after* a successful batch. Ignored
    ///   by mocks (which don't charge).
    /// - Precondition: caller has verified affordability (UX gate) AND
    ///   recorded explicit per-batch consent (see `DeepAnalysisConsentView`).
    func analyze(
        photos: [(assetID: String, jpegData: Data)],
        persona: Persona,
        appUserID: String
    ) async throws -> DeepVisionResult
}

enum AnalysisError: LocalizedError {
    case photoAccessDenied
    case emptyLibrary
    case cancelled
    case backendUnavailable(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "Photo library access was denied. Enable it in Settings to get roasted."
        case .emptyLibrary:
            return "No photos found in the selected time range."
        case .cancelled:
            return "Analysis was cancelled."
        case .backendUnavailable:
            return "Couldn't reach the insight service. Try again in a bit."
        }
    }
}
