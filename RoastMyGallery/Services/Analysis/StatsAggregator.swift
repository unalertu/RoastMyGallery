import Foundation

/// Stage 2: folds per-photo observations into the compact `PhotoStats` object
/// that gets serialized to JSON for the insight backend. Pure function of its
/// inputs — no I/O, trivially testable.
struct StatsAggregator: StatsAggregating {
    private let maxLocationClusters = 5

    /// Deep analysis feeds a much longer narrative, so it keeps a wider slice
    /// of the category distribution (the backend's allowed-category list grows
    /// to match — see backend/lib/prompts.js).
    private func maxTopCategories(for depth: AnalysisDepth) -> Int {
        depth == .deep ? 25 : 10
    }

    private func maxCategoriesPerMonth(for depth: AnalysisDepth) -> Int {
        depth == .deep ? 8 : 5
    }

    func aggregate(
        _ observations: [PhotoObservation],
        totalPhotos: Int,
        scope: AnalysisScope,
        depth: AnalysisDepth
    ) -> PhotoStats {
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
            //
            // Screenshots are deliberately excluded from scene categories:
            // `VNClassifyImageRequest` is unreliable on UI/text/solid-color
            // images (a black Notes screenshot reads as "sky", a white one as
            // "paper"), which both inflated bogus category counts and surfaced
            // screenshots as the representative photo for real topics. They're
            // still counted via `screenshotCount` and the "screenshot" tag.
            if !observation.isScreenshot {
                for scored in CategoryVocabulary.scoredTopics(for: observation.categories) {
                    categoryCounts[scored.topic, default: 0] += 1
                    if let monthKey {
                        monthlyCategoryCounts[monthKey, default: [:]][scored.topic, default: 0] += 1
                    }
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
            .prefix(maxTopCategories(for: depth))
            .map { CategoryCount(category: $0.key, count: $0.value) }

        let monthlyLimit = maxCategoriesPerMonth(for: depth)
        let categoriesByMonth = monthlyCategoryCounts.mapValues { counts in
            counts
                .sorted { $0.value > $1.value }
                .prefix(monthlyLimit)
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
    /// Scene categories keep their up-to-`maxAssetsPerCategory` HIGHEST-
    /// CONFIDENCE matches (across the whole scan), so a segment tagged "food"
    /// resolves to the strongest food photo, not merely the most recent one.
    /// Animal/selfie/screenshot tags have no scene-classification score, so
    /// they stay recency-ordered (observations arrive newest-first).
    /// DEVICE-ONLY: asset identifiers are never serialized to the backend.
    func photoIndex(for observations: [PhotoObservation]) -> [String: [String]] {
        // 3 keeps a little headroom for the results screen's cross-segment
        // de-duplication (so two beats sharing a category can show different
        // photos) without reaching so deep that weak matches surface.
        let maxAssetsPerCategory = 3
        var index: [String: [String]] = [:]

        func record(_ key: String, _ assetID: String) {
            var ids = index[key, default: []]
            guard ids.count < maxAssetsPerCategory, !ids.contains(assetID) else { return }
            ids.append(assetID)
            index[key] = ids
        }

        // Scene categories: gather every (topic, photo, confidence) candidate,
        // then record strongest-first so each topic keeps its best matches.
        // Screenshots are excluded — their scene classification is unreliable
        // (see `aggregate`), so they'd otherwise surface as bogus matches.
        var sceneCandidates: [(topic: String, assetID: String, confidence: Float)] = []
        for observation in observations where !observation.isScreenshot {
            for scored in CategoryVocabulary.scoredTopics(for: observation.categories) {
                sceneCandidates.append((scored.topic, observation.assetID, scored.confidence))
            }
        }
        for candidate in sceneCandidates.sorted(by: { $0.confidence > $1.confidence }) {
            record(candidate.topic, candidate.assetID)
        }

        // Animal / selfie / screenshot tags: recency-ordered, filling any
        // remaining slots (and their own keys).
        for observation in observations {
            for animal in observation.animals { record(animal, observation.assetID) }
            if observation.isSelfie { record("selfie", observation.assetID) }
            if observation.isScreenshot { record("screenshot", observation.assetID) }
        }
        return index
    }
}
