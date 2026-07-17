import Foundation
import Photos
import os

/// Deep-analysis captioning: uploads the downscaled photos the results screen
/// will display to `backend/api/photo-captions.js` (Gemini vision model) and
/// returns one short caption per photo, batch order preserved.
///
/// INVARIANTS:
/// - Runs only inside a deep analysis, after the user's explicit consent on
///   the deep setup screen (required-to-start; see PersonaPickerView).
/// - Costs nothing extra: the deep run's 5 gems were already charged by
///   `/api/insight`; this endpoint deducts 0 (see backend/api/photo-captions.js).
/// - Best-effort by contract: callers treat any failure as "no captions",
///   never as a failed analysis.
/// - Asset IDs stay on-device; only pixels + segment texts + persona go up.
struct BackendPhotoCaptionService: PhotoCaptioning {
    /// Capped below the backend's 16-image ceiling on purpose: a single
    /// vision call loses per-image fidelity as the batch grows (captions get
    /// generic, and the call creeps toward the timeout). 12 keeps captions
    /// sharp while still covering essentially every photo a deep result shows.
    /// Any photos beyond this simply render without a caption (best-effort).
    let maxBatchSize = 12

    var baseURL: URL = AppConfig.backendBaseURL
    var session: URLSession = .shared

    private struct CaptionRequest: Encodable {
        let appUserId: String
        let persona: Persona
        /// Lets the backend answer in the user's language.
        let locale: String
        /// Base64 JPEGs, in batch order — the order `captions` answers in.
        let images: [String]
        /// Parallel to `images`: the story beat each photo illustrates, so the
        /// caption can complement its card's text instead of repeating it.
        let contexts: [Context]
        let schemaVersion = 1

        struct Context: Encodable {
            let text: String
            let category: String?
        }
    }

    /// Contract with the backend: `{ captions: [String] }`, one per image in
    /// batch order — see backend/api/photo-captions.js.
    private struct CaptionResponse: Decodable {
        let captions: [String]
    }

    func captions(
        for photos: [CaptionPhoto],
        persona: Persona,
        appUserID: String
    ) async throws -> [String] {
        precondition(photos.count <= maxBatchSize, "Batch exceeds maxBatchSize")

        var request = URLRequest(url: baseURL.appending(path: "api/photo-captions"))
        request.httpMethod = "POST"
        // A few MB of upload plus multi-image vision latency.
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anti-abuse tripwire, not real auth — see AppConfig.appSharedSecret.
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Secret")
        request.httpBody = try JSONEncoder.backend.encode(
            CaptionRequest(
                appUserId: appUserID,
                persona: persona,
                locale: Locale.current.identifier,
                images: photos.map { $0.jpegData.base64EncodedString() },
                contexts: photos.map {
                    .init(text: $0.segmentText, category: $0.category)
                }
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PhotoCaptionError.network
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PhotoCaptionError.serviceUnavailable
        }

        do {
            return try JSONDecoder.backend.decode(CaptionResponse.self, from: data).captions
        } catch {
            throw PhotoCaptionError.serviceUnavailable
        }
    }
}

/// Internal-only failures (never shown to the user — captions are best-effort
/// and the deep story stands on its own without them).
enum PhotoCaptionError: Error {
    case network
    case serviceUnavailable
}

/// Loads and downscales caption-batch photos from their asset IDs.
/// Mirrors the Deep Vision upload path: original data is decoded at thumbnail
/// size only (`ImageDownscaler`), full-resolution bitmaps never materialize,
/// and full-resolution originals never leave the device.
enum CaptionPhotoLoader {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RoastMyGallery",
        category: "Captions"
    )

    /// Resolves each asset ID to an upload-ready JPEG; assets that fail to
    /// load are skipped (their cards simply render without a caption).
    static func loadJPEGs(for photos: [(assetID: String, segmentText: String, category: String?)]) async -> [CaptionPhoto] {
        let budget = ImageDownscaler.perPhotoBudget(batchSize: photos.count)
        var result: [CaptionPhoto] = []
        for photo in photos {
            guard let jpeg = await uploadJPEG(assetID: photo.assetID, budget: budget) else {
                Self.logger.warning("Caption photo unavailable, skipping one asset")
                continue
            }
            result.append(CaptionPhoto(
                assetID: photo.assetID,
                jpegData: jpeg,
                segmentText: photo.segmentText,
                category: photo.category
            ))
        }
        return result
    }

    private static func uploadJPEG(assetID: String, budget: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                .firstObject else { return nil }

            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            // Originals may live in iCloud; the downscale below keeps the
            // upload small regardless of what comes back.
            options.isNetworkAccessAllowed = true

            var original: Data?
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                original = data
            }
            guard let original else { return nil }
            return ImageDownscaler.uploadJPEG(from: original, budgetBytes: budget)
        }.value
    }
}
