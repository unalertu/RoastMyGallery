import Foundation

/// Graceful degradation: try the real backend first; if it's unreachable or
/// errors, fall back to the local mock so the user still gets a result
/// instead of an error screen. Cancellation is never swallowed — backing out
/// of a scan must not trigger a fallback insight.
struct FallbackInsightGenerator: InsightGenerating {
    let primary: InsightGenerating
    let fallback: InsightGenerating

    func generateInsight(from stats: PhotoStats, persona: Persona, appUserID: String) async throws -> Insight {
        do {
            return try await primary.generateInsight(from: stats, persona: persona, appUserID: appUserID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // TODO: route through a proper logger + surface "offline mode"
            // subtly in the UI if product wants that distinction.
            // NOTE: the fallback is local (no backend), so a fallback insight is
            // NOT charged — the credit deduct lives in the backend endpoint.
            try Task.checkCancellation()
            return try await fallback.generateInsight(from: stats, persona: persona, appUserID: appUserID)
        }
    }
}
