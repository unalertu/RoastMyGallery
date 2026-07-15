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
        shareLine: "You have more screenshots than memories and a very busy cat.",
        superlatives: stats.cardSuperlatives
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
#endif
