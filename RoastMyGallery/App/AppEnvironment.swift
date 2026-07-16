import Foundation

/// Composition root: wires concrete implementations to the pipeline protocols.
/// This is the ONE place to swap mocks for real services.
struct AppEnvironment {
    let photoLibrary: PhotoLibraryProviding
    let analyzer: PhotoAnalyzing
    let aggregator: StatsAggregating
    let insightGenerator: InsightGenerating
    let deepVision: DeepVisionAnalyzing
    let photoCaptions: PhotoCaptioning

    /// Real on-device analysis + real insight backend (Gemini via Vercel).
    /// No offline/outage fallback — a failed insight surfaces as a calm error
    /// with a "Try Again" retry, the same as Deep Vision, rather than silently
    /// serving canned text that looks like a real (but low-quality) result.
    static func live() -> AppEnvironment {
        let library = PhotoLibraryService()
        return AppEnvironment(
            photoLibrary: library,
            analyzer: OnDeviceAnalyzer(library: library),
            aggregator: StatsAggregator(),
            insightGenerator: BackendInsightGenerator(), // URL: AppConfig.backendBaseURL
            deepVision: BackendDeepVisionService(),
            photoCaptions: BackendPhotoCaptionService()
        )
    }
}
