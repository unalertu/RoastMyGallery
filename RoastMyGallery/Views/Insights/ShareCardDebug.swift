#if DEBUG
import SwiftUI

/// Sample data for share-card previews and debug rendering — realistic
/// numbers so layout issues show up (long category names, big counts).
enum ShareCardSampleData {
    static let stats = PhotoStats(
        generatedAt: .now,
        scope: .lastThreeMonths,
        totalPhotos: 812,
        analyzedPhotos: 812,
        selfieCount: 214,
        screenshotCount: 301,
        favoriteCount: 12,
        faceCountBuckets: ["0": 400, "1": 300, "2+": 112],
        topCategories: [
            CategoryCount(category: "food", count: 190),
            CategoryCount(category: "cat", count: 121),
            CategoryCount(category: "sunset", count: 87),
        ],
        categoriesByMonth: [:],
        photosByMonth: ["2026-05": 250, "2026-06": 300, "2026-07": 262],
        photosByHourOfDay: [5, 2, 1, 40, 0, 0, 0, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 90, 60, 40, 20, 10, 2],
        topLocationClusters: [LocationClusterStat(share: 0.87, label: "cluster-1")],
        animalCounts: ["cat": 44]
    )

    static let insight = Insight(
        id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
        persona: .roast,
        generatedAt: .now,
        headline: "The Unofficial Digital Hoarder",
        body: "Your library is a cry for help disguised as a scrapbook…",
        segments: [
            .init(
                text: "Let's address the elephant in the camera roll: 301 screenshots. Recipes you'll never cook, arguments you won, error messages you were definitely going to google later.",
                category: nil
            ),
            .init(
                text: "One hundred and ninety photos of food. Not eating it — photographing it. Somewhere a plate of pasta went cold for your art, and honestly? It wasn't even that photogenic.",
                category: "food"
            ),
            .init(
                text: "And then there's the cat. Forty-four dedicated portraits of an animal that has never once consented to a photoshoot. The cat is not your muse. The cat wants lunch.",
                category: "cat"
            ),
            .init(
                text: "June was your busiest month — 300 photos. That's ten a day. Nobody's life is that interesting, but your storage plan sure believes it is.",
                category: nil
            ),
        ],
        shareLine: "You have more screenshots than memories and a very busy cat.",
        superlatives: stats.cardSuperlatives
    )

    /// A full record for Full Story panel rendering. No `categoryPhotoIndex`
    /// on purpose — debug panels render text-only (photo loading needs a real
    /// photo library).
    static let record = AnalysisRecord(
        id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
        createdAt: .now,
        persona: .roast,
        insight: insight,
        stats: stats
    )
}

/// Launch with `--render-share-cards` (simulator) to write PNGs of every card
/// design/variant to the app's Documents directory using sample data — lets
/// the card visuals be reviewed without tapping through the flow.
@MainActor
enum ShareCardDebugExporter {
    static func renderAllIfRequested() {
        guard CommandLine.arguments.contains("--render-share-cards") else { return }
        let directory = URL.documentsDirectory
        do {
            let classic = try ShareCardRenderer()
                .renderCard(insight: ShareCardSampleData.insight, stats: ShareCardSampleData.stats)
            try classic.pngData()?.write(to: directory.appending(path: "card-classic.png"))

            for variant in AltCardVariant.all {
                let image = try AltShareCardRenderer(variant: variant)
                    .renderCard(insight: ShareCardSampleData.insight, stats: ShareCardSampleData.stats)
                try image.pngData()?.write(to: directory.appending(path: "card-editorial-\(variant.name).png"))
            }
            print("[share-cards] wrote PNGs to \(directory.path)")
        } catch {
            print("[share-cards] render failed: \(error)")
        }

        // Full Story panels render text-only here (no photo library in the
        // sample record) — async because the builder's photo step is.
        Task { @MainActor in
            do {
                let record = ShareCardSampleData.record
                let panels = await FullStoryBuilder.panels(for: record)
                let images = try await FullStoryRenderer().render(record: record, panels: panels)
                for (index, image) in images.enumerated() {
                    try image.pngData()?.write(to: directory.appending(path: "card-fullstory-\(index + 1).png"))
                }
                print("[share-cards] wrote \(images.count) Full Story panels to \(directory.path)")
            } catch {
                print("[share-cards] Full Story render failed: \(error)")
            }
        }
    }
}

#Preview("Editorial · blush") {
    AltShareCardView(insight: ShareCardSampleData.insight, stats: ShareCardSampleData.stats, variant: .blush)
}

#Preview("Editorial · meadow") {
    AltShareCardView(insight: ShareCardSampleData.insight, stats: ShareCardSampleData.stats, variant: .meadow)
}

#Preview("Editorial · sky") {
    AltShareCardView(insight: ShareCardSampleData.insight, stats: ShareCardSampleData.stats, variant: .sky)
}

#Preview("Full Story · cover") {
    FullStoryPanelView(
        record: ShareCardSampleData.record,
        panel: .cover,
        index: 1,
        total: 4,
        variant: .blush
    )
}

#Preview("Full Story · beats") {
    FullStoryPanelView(
        record: ShareCardSampleData.record,
        panel: .beats(
            (ShareCardSampleData.insight.segments ?? []).prefix(2).map {
                FullStoryPanel.ResolvedBeat(text: $0.text, photo: nil, caption: nil)
            }
        ),
        index: 2,
        total: 4,
        variant: .blush
    )
}

#Preview("Full Story · closing") {
    FullStoryPanelView(
        record: ShareCardSampleData.record,
        panel: .closing(hiddenBeatCount: 3),
        index: 4,
        total: 4,
        variant: .blush
    )
}
#endif
