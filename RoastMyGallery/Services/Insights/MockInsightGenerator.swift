import Foundation

/// Local stand-in for the LLM backend. Produces canned-but-stats-aware copy so
/// the whole flow (scan → insight → share card) works end-to-end with no
/// network. Swap for `BackendInsightGenerator` in `AppEnvironment`.
struct MockInsightGenerator: InsightGenerating {
    /// Artificial latency so loading states are visible during development.
    var simulatedDelay: Duration = .seconds(1.5)

    func generateInsight(from stats: PhotoStats, persona: Persona, appUserID: String) async throws -> Insight {
        // appUserID is unused: the mock is local and never charges credits.
        try await Task.sleep(for: simulatedDelay)

        let topCategory = stats.topCategories.first?.category ?? "absolutely nothing"
        let selfiePercent = Int(stats.selfieRatio * 100)
        let peakHour = stats.photosByHourOfDay.enumerated().max(by: { $0.element < $1.element })?.offset ?? 12

        // Category tags mirror the backend contract: only values that exist
        // in this user's stats (so the results screen can match a photo).
        let topCategoryTag = stats.topCategories.first?.category
        let selfieTag: String? = stats.selfieCount > 0 ? "selfie" : nil
        let screenshotTag: String? = stats.screenshotCount > 0 ? "screenshot" : nil

        switch persona {
        case .roast:
            let segments: [Insight.Segment] = [
                .init(
                    text: "\(stats.analyzedPhotos) photos and somehow \"\(topCategory)\" is your whole personality.",
                    category: topCategoryTag
                ),
                .init(
                    text: "A \(selfiePercent)% selfie ratio means your front camera has filed for workers' comp.",
                    category: selfieTag
                ),
                .init(
                    text: "And \(stats.screenshotCount) screenshots you will absolutely never look at again.",
                    category: screenshotTag
                ),
                .init(
                    text: "Peak activity at \(peakHour):00 — we both know what that says about your sleep schedule.",
                    category: nil
                ),
            ]
            return Insight(
                id: UUID(),
                persona: .roast,
                generatedAt: .now,
                headline: "Certified \(topCategory.capitalized) Paparazzo",
                body: segments.map(\.text).joined(separator: "\n\n"),
                segments: segments,
                shareLine: "The front camera has filed for workers' comp.",
                superlatives: [
                    .init(title: "Top obsession", detail: topCategory),
                    .init(title: "Selfie ratio", detail: "\(selfiePercent)% — the front camera is tired"),
                    .init(title: "Screenshot hoard", detail: "\(stats.screenshotCount) and counting"),
                    .init(title: "Witching hour", detail: "\(peakHour):00"),
                ],
                isPreview: true
            )
        case .analyst:
            let segments: [Insight.Segment] = [
                .init(
                    text: "Across \(stats.analyzedPhotos) photos, a clear theme emerges: \"\(topCategory)\" anchors how you document your life.",
                    category: topCategoryTag
                ),
                .init(
                    text: "Your \(selfiePercent)% selfie ratio suggests you see yourself as a participant in your memories, not just an observer.",
                    category: selfieTag
                ),
                .init(
                    text: "The rhythm of your captures — peaking around \(peakHour):00 — hints at when you feel most present.",
                    category: nil
                ),
            ]
            return Insight(
                id: UUID(),
                persona: .analyst,
                generatedAt: .now,
                headline: "The \(topCategory.capitalized) Chronicler",
                body: segments.map(\.text).joined(separator: "\n\n"),
                segments: segments,
                shareLine: "You photograph the life you're paying attention to.",
                superlatives: [
                    .init(title: "Core theme", detail: topCategory),
                    .init(title: "Self-presence", detail: "\(selfiePercent)% of frames include you"),
                    .init(title: "Most alive at", detail: "\(peakHour):00"),
                ],
                isPreview: true
            )
        }
    }
}
