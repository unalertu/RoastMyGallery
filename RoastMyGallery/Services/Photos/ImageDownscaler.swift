import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales/re-encodes picked photos before a Deep Vision upload.
///
/// Full-resolution originals must NEVER be uploaded (privacy contract, upload
/// size, and Gemini cost). Every image goes through here first: decode at
/// thumbnail size via ImageIO (no full-size decode in memory), then JPEG-
/// encode stepping down dimension/quality until the per-photo byte budget is
/// met. The budget shrinks with batch size so a full 30-photo batch stays
/// comfortably under the backend's payload caps (see api/deep-vision.js).
enum ImageDownscaler {
    /// Longest edge of an uploaded image, tried in order.
    private static let maxPixelSteps: [CGFloat] = [1024, 768, 640]
    private static let qualitySteps: [Double] = [0.6, 0.45, 0.35]

    /// Total binary budget per batch: ~2.6 MB → ~3.5 M base64 chars, under
    /// both the server's 3.9 M-char cap and Vercel's 4.5 MB body limit.
    private static let batchBudgetBytes = 2_600_000

    /// Per-photo byte budget for a batch of `batchSize` photos.
    static func perPhotoBudget(batchSize: Int) -> Int {
        max(60_000, min(220_000, batchBudgetBytes / max(batchSize, 1)))
    }

    /// Re-encodes `data` (any image format the system can read) as an
    /// upload-ready JPEG at most ~1024 px on the long edge, aiming for
    /// `budgetBytes`. Returns the first variant within budget, else the
    /// smallest one produced; nil only when the data can't be decoded at all.
    static func uploadJPEG(from data: Data, budgetBytes: Int) -> Data? {
        var smallest: Data?
        for maxPixelSize in maxPixelSteps {
            guard let image = downsampled(data, maxPixelSize: maxPixelSize) else { continue }
            for quality in qualitySteps {
                guard let jpeg = jpegData(image, quality: quality) else { continue }
                if jpeg.count <= budgetBytes { return jpeg }
                if smallest == nil || jpeg.count < smallest!.count { smallest = jpeg }
            }
        }
        return smallest
    }

    /// Thumbnail-sized decode straight from the source data — never
    /// materializes the full-resolution bitmap.
    private static func downsampled(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bake EXIF orientation into the pixels so the model (and our
            // previews) see the photo the right way up.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    private static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
