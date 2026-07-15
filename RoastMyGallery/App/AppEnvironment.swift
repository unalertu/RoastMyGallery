import Foundation

/// Composition root: wires concrete implementations to the pipeline protocols.
/// This is the ONE place to swap mocks for real services.
struct AppEnvironment {
    let photoLibrary: PhotoLibraryProviding
    let analyzer: PhotoAnalyzing
    let aggregator: StatsAggregating
    let insightGenerator: InsightGenerating
    let deepVision: DeepVisionAnalyzing

    /// Real on-device analysis + real insight backend (Gemini via Vercel),
    /// with the mock as an offline/outage fallback. Deep Vision is real too
    /// (no offline fallback on purpose — it's a paid upload, so failures
    /// surface as calm errors instead of canned text).
    static func live() -> AppEnvironment {
        let library = PhotoLibraryService()
        return AppEnvironment(
            photoLibrary: library,
            analyzer: OnDeviceAnalyzer(library: library),
            aggregator: StatsAggregator(),
            insightGenerator: FallbackInsightGenerator(
                primary: BackendInsightGenerator(), // URL: AppConfig.backendBaseURL
                fallback: MockInsightGenerator(simulatedDelay: .seconds(0.6))
            ),
            deepVision: BackendDeepVisionService()
        )
    }
}
