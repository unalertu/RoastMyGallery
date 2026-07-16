import Foundation
import Photos
import Vision
import UIKit
import os

/// Stage 1 implementation: enumerates the library via `PhotoLibraryProviding`,
/// downsamples each asset to a small thumbnail, and runs Vision requests
/// (classification, face rectangles, animal recognition) fully on-device.
///
/// Concurrency model: assets are processed in a `TaskGroup` capped at
/// `maxConcurrentRequests` so large libraries don't spike memory, with
/// progress reported after every completed asset. Cancellation propagates
/// through the group.
final class OnDeviceAnalyzer: PhotoAnalyzing {
    private let library: PhotoLibraryProviding

    /// Thumbnail edge used for Vision. 512px is plenty for classification and
    /// face counting while keeping decode cost low.
    private let targetSize = CGSize(width: 512, height: 512)
    private let maxConcurrentRequests = 4
    /// Minimum confidence for a classification label to be kept.
    private let classificationThreshold: Float = 0.4
    /// Keep at most this many labels per photo so stats stay compact. Kept a
    /// little generous because `CategoryVocabulary` drops filler labels and
    /// merges synonyms downstream, so a few raw labels survive into topics.
    private let maxCategoriesPerPhoto = 5

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RoastMyGallery",
        category: "Scan"
    )

    init(library: PhotoLibraryProviding) {
        self.library = library
    }

    func analyze(
        scope: AnalysisScope,
        onProgress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> ScanOutput {
        let fetchResult = library.fetchAssets(in: scope)
        guard fetchResult.count > 0 else { throw AnalysisError.emptyLibrary }
        Self.logger.info("Scan '\(scope.displayLabel, privacy: .public)': fetched \(fetchResult.count) assets")

        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }

        let selfieIDs = library.selfieAssetIDs()
        let total = assets.count
        let progressCounter = ProgressCounter()

        var observations: [PhotoObservation] = []
        observations.reserveCapacity(total)

        // Sliding-window task group: at most `maxConcurrentRequests` in flight.
        try await withThrowingTaskGroup(of: PhotoObservation?.self) { group in
            var iterator = assets.makeIterator()

            func addNextTask() -> Bool {
                guard let asset = iterator.next() else { return false }
                group.addTask { [self] in
                    try Task.checkCancellation()
                    let observation = await self.observe(asset: asset, isSelfie: selfieIDs.contains(asset.localIdentifier))
                    let done = await progressCounter.increment()
                    onProgress(AnalysisProgress(completed: done, total: total))
                    return observation
                }
                return true
            }

            for _ in 0..<maxConcurrentRequests where addNextTask() {}

            while let observation = try await group.next() {
                if let observation { observations.append(observation) }
                _ = addNextTask()
            }
        }

        let skipped = total - observations.count
        Self.logger.info("Scan '\(scope.displayLabel, privacy: .public)': analyzed \(observations.count)/\(total) assets (\(skipped) skipped)")
        return ScanOutput(totalAssets: total, observations: observations)
    }

    // MARK: - Per-asset work

    /// Runs all Vision requests for one asset. Returns `nil` if the thumbnail
    /// couldn't be loaded (e.g. iCloud asset offline) — the photo still counts
    /// toward progress but not toward analyzed stats.
    private func observe(asset: PHAsset, isSelfie: Bool) async -> PhotoObservation? {
        guard let cgImage = await loadThumbnail(for: asset) else { return nil }

        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([classify, faces, animals])
        } catch {
            // A single failed photo shouldn't sink the scan; log and skip.
            Self.logger.warning("Vision failed for asset, skipping: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let categories = (classify.results ?? [])
            .filter { $0.confidence >= classificationThreshold }
            .prefix(maxCategoriesPerPhoto)
            .map(\.identifier)

        let animalLabels = (animals.results ?? []).flatMap { observation in
            observation.labels.map(\.identifier)
        }

        let coarseLocation = asset.location.map {
            CoarseLocation(
                roundingLatitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }

        return PhotoObservation(
            assetID: asset.localIdentifier,
            creationDate: asset.creationDate,
            coarseLocation: coarseLocation,
            isSelfie: isSelfie,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isFavorite: asset.isFavorite,
            faceCount: faces.results?.count ?? 0,
            categories: Array(categories),
            animals: Array(Set(animalLabels))
        )
    }

    /// Loads the analysis thumbnail, trying a local-only request first and
    /// falling back to allowing network access.
    ///
    /// The fallback matters: with iCloud Photos set to "Optimize iPhone
    /// Storage" most originals are NOT on device, and a local-only
    /// `.highQualityFormat` request returns nil for them — without the retry
    /// those photos would be silently missing from every stat (the classic
    /// "analyzed 61 photos in a 900-photo month" bug). Only the ~512px
    /// derivative is fetched, never the full original, and Vision still runs
    /// entirely on-device, so the privacy contract is unchanged.
    private func loadThumbnail(for asset: PHAsset) async -> CGImage? {
        if let local = await requestThumbnail(for: asset, allowNetwork: false) {
            return local
        }
        let remote = await requestThumbnail(for: asset, allowNetwork: true)
        if remote == nil {
            Self.logger.warning("Thumbnail unavailable (even via iCloud), skipping asset")
        }
        return remote
    }

    /// Async wrapper around PHImageManager. `deliveryMode = .highQualityFormat`
    /// guarantees the handler fires exactly once, which keeps the continuation safe.
    private func requestThumbnail(for asset: PHAsset, allowNetwork: Bool) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}

/// Serializes progress increments across the concurrent task group.
private actor ProgressCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}
