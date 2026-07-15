import Foundation
import Photos
import Vision
import UIKit

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
    /// Keep at most this many labels per photo so stats stay compact.
    private let maxCategoriesPerPhoto = 3

    init(library: PhotoLibraryProviding) {
        self.library = library
    }

    func analyze(
        scope: AnalysisScope,
        onProgress: @escaping @Sendable (AnalysisProgress) -> Void
    ) async throws -> [PhotoObservation] {
        let fetchResult = library.fetchAssets(in: scope)
        guard fetchResult.count > 0 else { throw AnalysisError.emptyLibrary }

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

        return observations
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
            // TODO: route through a proper logger.
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

    /// Async wrapper around PHImageManager. `deliveryMode = .highQualityFormat`
    /// guarantees the handler fires exactly once, which keeps the continuation safe.
    private func loadThumbnail(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false // never pull originals from iCloud during a scan
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
