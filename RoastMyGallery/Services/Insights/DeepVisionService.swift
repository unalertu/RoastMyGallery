import Foundation

/// Pro-tier deep analysis, mocked. The real implementation will upload the
/// consented photo batch to the backend's vision-LLM endpoint.
///
/// INVARIANTS the real implementation must keep:
/// - Called only after `PurchaseManager.entitlements.canUseDeepAnalysis`.
/// - Called only with photos the user picked in an explicit per-batch consent
///   flow (`DeepAnalysisConsentView`) — never auto-selected.
/// - Asset IDs are used client-side to map results back; only pixel data and
///   the persona are uploaded.
struct MockDeepVisionService: DeepVisionAnalyzing {
    let maxBatchSize = 30

    func analyze(
        photos: [(assetID: String, jpegData: Data)],
        persona: Persona
    ) async throws -> [PhotoCommentary] {
        precondition(photos.count <= maxBatchSize, "Batch exceeds maxBatchSize")
        try await Task.sleep(for: .seconds(2))

        // TODO: Replace with a real call:
        //   POST {backend}/v1/deep-analysis  (multipart: photos + persona)
        // The backend forwards to a vision-capable LLM and returns commentary
        // in upload order; map back to asset IDs client-side as below.
        return photos.map { photo in
            PhotoCommentary(
                id: UUID(),
                assetID: photo.assetID,
                comment: persona == .roast
                    ? "Bold of you to consider this one of your top 30."
                    : "This photo suggests a moment you genuinely wanted to keep."
            )
        }
    }
}
