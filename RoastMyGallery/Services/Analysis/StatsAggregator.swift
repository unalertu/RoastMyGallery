import Foundation

/// Stage 2: folds per-photo observations into the compact `PhotoStats` object
/// that gets serialized to JSON for the insight backend. Pure function of its
/// inputs — no I/O, trivially testable.
struct StatsAggregator: StatsAggregating {
    private let maxTopCategories = 10
    private let maxLocationClusters = 5
    private let maxCategoriesPerMonth = 5

    func aggregate(_ observations: [PhotoObservation], totalPhotos: Int, scope: AnalysisScope) -> PhotoStats {
        var categoryCounts: [String: Int] = [:]
        var monthlyCategoryCounts: [String: [String: Int]] = [:]
        var photosByMonth: [String: Int] = [:]
        var hourBuckets = [Int](repeating: 0, count: 24)
        var faceBuckets: [String: Int] = ["0": 0, "1": 0, "2+": 0]
        var locationCounts: [CoarseLocation: Int] = [:]
        var animalCounts: [String: Int] = [:]
        var selfieCount = 0
        var screenshotCount = 0
        var favoriteCount = 0

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let calendar = Calendar.current

        for observation in observations {
            if observation.isSelfie { selfieCount += 1 }
            if observation.isScreenshot { screenshotCount += 1 }
            if observation.isFavorite { favoriteCount += 1 }

            switch observation.faceCount {
            case 0: faceBuckets["0", default: 0] += 1
            case 1: faceBuckets["1", default: 0] += 1
            default: faceBuckets["2+", default: 0] += 1
            }

            var monthKey: String?
            if let date = observation.creationDate {
                let key = monthFormatter.string(from: date)
                monthKey = key
                photosByMonth[key, default: 0] += 1
                hourBuckets[calendar.component(.hour, from: date)] += 1
            }

            // Map raw Vision labels onto the friendly topic vocabulary before
            // counting, so synonyms merge, filler is dropped, and the keys here
            // match the ones `photoIndex` records (see CategoryVocabulary).
            for category in CategoryVocabulary.topics(for: observation.categories) {
                categoryCounts[category, default: 0] += 1
                if let monthKey {
                    monthlyCategoryCounts[monthKey, default: [:]][category, default: 0] += 1
                }
            }

            for animal in observation.animals {
                animalCounts[animal, default: 0] += 1
            }

            if let location = observation.coarseLocation {
                locationCounts[location, default: 0] += 1
            }
        }

        let topCategories = categoryCounts
            .sorted { $0.value > $1.value }
            .prefix(maxTopCategories)
            .map { CategoryCount(category: $0.key, count: $0.value) }

        let categoriesByMonth = monthlyCategoryCounts.mapValues { counts in
            counts
                .sorted { $0.value > $1.value }
                .prefix(maxCategoriesPerMonth)
                .map { CategoryCount(category: $0.key, count: $0.value) }
        }

        // Convert location clusters into anonymous shares — cell coordinates
        // are dropped here so they can never be serialized upstream.
        let locatedTotal = locationCounts.values.reduce(0, +)
        let topLocationClusters = locationCounts
            .sorted { $0.value > $1.value }
            .prefix(maxLocationClusters)
            .enumerated()
            .map { index, entry in
                LocationClusterStat(
                    share: locatedTotal > 0 ? Double(entry.value) / Double(locatedTotal) : 0,
                    label: "cluster-\(index + 1)"
                )
            }

        return PhotoStats(
            generatedAt: .now,
            scope: scope,
            totalPhotos: totalPhotos,
            analyzedPhotos: observations.count,
            selfieCount: selfieCount,
            screenshotCount: screenshotCount,
            favoriteCount: favoriteCount,
            faceCountBuckets: faceBuckets,
            topCategories: topCategories,
            categoriesByMonth: categoriesByMonth,
            photosByMonth: photosByMonth,
            photosByHourOfDay: hourBuckets,
            topLocationClusters: topLocationClusters,
            animalCounts: animalCounts
        )
    }

    /// Builds the category → representative asset IDs map used to show a
    /// matching photo under insight segments. Keys mirror the backend's
    /// allowed-category vocabulary: Vision category labels, animal labels,
    /// plus the synthetic "selfie" / "screenshot" tags.
    ///
    /// Observations arrive newest-first (see `PhotoLibraryService.fetchAssets`),
    /// so the first two asset IDs recorded per key are the most recent matches.
    /// DEVICE-ONLY: asset identifiers are never serialized to the backend.
    func photoIndex(for observations: [PhotoObservation]) -> [String: [String]] {
        let maxAssetsPerCategory = 2
        var index: [String: [String]] = [:]

        func record(_ key: String, _ assetID: String) {
            var ids = index[key, default: []]
            guard ids.count < maxAssetsPerCategory, !ids.contains(assetID) else { return }
            ids.append(assetID)
            index[key] = ids
        }

        for observation in observations {
            // Same friendly-topic mapping as `aggregate`, so a segment tagged
            // e.g. "food" resolves to a photo indexed under "food".
            for category in CategoryVocabulary.topics(for: observation.categories) {
                record(category, observation.assetID)
            }
            for animal in observation.animals { record(animal, observation.assetID) }
            if observation.isSelfie { record("selfie", observation.assetID) }
            if observation.isScreenshot { record("screenshot", observation.assetID) }
        }
        return index
    }
}
