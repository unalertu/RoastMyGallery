import Foundation

/// Hand-picked Deep Vision: uploads the consented, already-downscaled photo
/// batch to `backend/api/deep-vision.js` (a Vercel function wrapping Gemini's
/// vision model) and maps the returned batch-index references back to local
/// asset IDs.
///
/// INVARIANTS:
/// - Called only when the user can afford it (`PurchaseManager.deepVisionCost`
///   gems); the 5-gem charge is issued by the backend after success.
/// - Called only with photos the user picked in an explicit per-batch consent
///   flow (`DeepVisionFlowView`) — never auto-selected.
/// - Asset IDs are used client-side to map results back; only pixel data,
///   the persona, and the RevenueCat App User ID are uploaded.
/// - Photos must already be downscaled (`ImageDownscaler`) — never originals.
struct BackendDeepVisionService: DeepVisionAnalyzing {
    let maxBatchSize = 30

    var baseURL: URL = AppConfig.backendBaseURL
    var session: URLSession = .shared

    private struct DeepVisionRequest: Encodable {
        let appUserId: String
        let persona: Persona
        /// Lets the backend answer in the user's language.
        let locale: String
        /// Base64 JPEGs, in batch order — the order the backend's
        /// `photoIndexes` refer back to.
        let images: [String]
        /// Charge-idempotency token: stable across retries of the same batch,
        /// so the backend deducts at most once per (user, runId) even when a
        /// response is lost mid-flight. See backend/lib/idempotency.js.
        let runId: String
        let schemaVersion = 1
    }

    /// Contract with the backend: `{ summary, segments, generatedAt }` where
    /// each segment references photos by their index in the uploaded batch —
    /// see backend/api/deep-vision.js.
    private struct DeepVisionResponse: Decodable {
        let summary: String
        let segments: [Segment]
        let generatedAt: Date

        struct Segment: Decodable {
            let photoIndexes: [Int]
            let text: String
        }
    }

    func analyze(
        photos: [(assetID: String, jpegData: Data)],
        persona: Persona,
        appUserID: String,
        runID: UUID
    ) async throws -> DeepVisionResult {
        precondition(photos.count <= maxBatchSize, "Batch exceeds maxBatchSize")

        var request = URLRequest(url: baseURL.appending(path: "api/deep-vision"))
        request.httpMethod = "POST"
        // Generous: a few MB of upload plus multi-image vision latency.
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anti-abuse tripwire, not real auth — see AppConfig.appSharedSecret.
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Secret")
        request.httpBody = try JSONEncoder.backend.encode(
            DeepVisionRequest(
                appUserId: appUserID,
                persona: persona,
                locale: Locale.current.identifier,
                images: photos.map { $0.jpegData.base64EncodedString() },
                runId: runID.uuidString
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw DeepVisionError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepVisionError.serviceUnavailable
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 402:
            throw DeepVisionError.insufficientGems
        case 413:
            throw DeepVisionError.batchTooLarge
        case 429:
            throw DeepVisionError.rateLimited
        default:
            throw DeepVisionError.serviceUnavailable
        }

        let decoded: DeepVisionResponse
        do {
            decoded = try JSONDecoder.backend.decode(DeepVisionResponse.self, from: data)
        } catch {
            throw DeepVisionError.serviceUnavailable
        }

        // Map batch indexes back to local asset IDs — this side of the wire
        // is the only place both halves of the mapping exist.
        let segments = decoded.segments.map { segment in
            DeepVisionResult.Segment(
                id: UUID(),
                assetIDs: segment.photoIndexes.compactMap { index in
                    photos.indices.contains(index) ? photos[index].assetID : nil
                },
                text: segment.text
            )
        }
        return DeepVisionResult(summary: decoded.summary, segments: segments)
    }
}

/// User-facing failures of a Deep Vision batch. Calm copy; and because the
/// backend deducts only after success, every one of these means no gems
/// were spent.
enum DeepVisionError: LocalizedError, Equatable {
    case insufficientGems
    case rateLimited
    case batchTooLarge
    case network
    case serviceUnavailable
    /// No picked photo could be read/downscaled.
    case preparationFailed

    var errorDescription: String? {
        switch self {
        case .insufficientGems:
            return "Not enough gems for this batch. No gems were taken."
        case .rateLimited:
            return "The analysis service is busy right now. Try again in a minute — no gems were taken."
        case .batchTooLarge:
            return "That batch is too large to upload. Try picking fewer photos."
        // These two can fire AFTER the server already finished (a response
        // lost in transit) — in that rare case the gems were taken, and the
        // retry redeems them: the same run is never charged twice (see
        // backend/lib/idempotency.js). So promise exactly that, not "nothing
        // was taken".
        case .network:
            return "Couldn't reach the analysis service. Check your connection and try again — you'll never be charged twice for the same batch."
        case .serviceUnavailable:
            return "The analysis service had a hiccup. Try again in a bit — you'll never be charged twice for the same batch."
        case .preparationFailed:
            return "Those photos couldn't be prepared for upload. Try picking different ones."
        }
    }
}

/// Offline/preview stand-in. Never uploads, never charges.
struct MockDeepVisionService: DeepVisionAnalyzing {
    let maxBatchSize = 30

    func analyze(
        photos: [(assetID: String, jpegData: Data)],
        persona: Persona,
        appUserID: String,
        runID: UUID
    ) async throws -> DeepVisionResult {
        precondition(photos.count <= maxBatchSize, "Batch exceeds maxBatchSize")
        try await Task.sleep(for: .seconds(2))

        return DeepVisionResult(
            summary: persona == .roast
                ? "A camera roll curated with confidence, if not consistency."
                : "A batch full of moments you clearly wanted to hold on to.",
            segments: photos.map { photo in
                DeepVisionResult.Segment(
                    id: UUID(),
                    assetIDs: [photo.assetID],
                    text: persona == .roast
                        ? "Bold of you to consider this one of your top 30."
                        : "This photo suggests a moment you genuinely wanted to keep."
                )
            }
        )
    }
}
