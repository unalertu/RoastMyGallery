import Foundation

/// Stage 3 implementation that calls the app's own backend
/// (`backend/api/insight.js` — a Vercel function wrapping Gemini).
/// The Gemini API key lives server-side only; this client never sees it.
///
/// PRIVACY: the request body is exactly `PhotoStats` + persona + locale.
/// No images, no asset IDs, no precise locations (see the `PhotoStats`
/// privacy contract).
struct BackendInsightGenerator: InsightGenerating {
    var baseURL: URL = AppConfig.backendBaseURL
    var session: URLSession = .shared

    private struct InsightRequest: Encodable {
        let stats: PhotoStats
        let persona: Persona
        /// Lets the backend answer in the user's language.
        let locale: String
        /// RevenueCat App User ID. The backend deducts 1 CRD for this customer
        /// *after* a successful generation (deduct-after-success). Optional on
        /// the wire so older/mock paths can omit it.
        let appUserId: String
        /// Advances per re-generation of the same stats; the backend maps it to
        /// a narrative lens + spotlight topics (see backend/lib/prompts.js).
        let variationSeed: Int
        /// "deep" for deep runs; nil (omitted from the JSON) for standard.
        /// Omitting it on standard keeps the request wire-identical to older
        /// builds, so a standard analysis works against ANY backend version —
        /// only Deep Analysis requires the depth-aware backend to be deployed.
        /// (Swift's synthesized encoder skips nil optionals, and the backend
        /// treats a missing `depth` as "standard".)
        let depth: String?
        /// Charge-idempotency token: stable across retries of the same run,
        /// so the backend deducts at most once per (user, runId) even when a
        /// response is lost mid-flight. See backend/lib/idempotency.js.
        let runId: String
        /// Bump when the stats schema changes so the backend can branch.
        let schemaVersion = 1
    }

    /// Contract with the backend:
    /// `{ insightText, shareLine, segments, generatedAt }`, where the first
    /// line of `insightText` is the headline, `shareLine` is a quotable
    /// one-liner, and `segments` is the narrative split into category-tagged
    /// beats (null when the model fell back to plain text) — see
    /// backend/lib/prompts.js and backend/api/insight.js.
    private struct InsightResponse: Decodable {
        let insightText: String
        let shareLine: String?
        let segments: [Insight.Segment]?
        let generatedAt: Date
    }

    func generateInsight(
        from stats: PhotoStats,
        persona: Persona,
        appUserID: String,
        variationSeed: Int,
        depth: AnalysisDepth,
        runID: UUID
    ) async throws -> Insight {
        var request = URLRequest(url: baseURL.appending(path: "api/insight"))
        request.httpMethod = "POST"
        // Deep runs a stronger model over a 3× output budget — give it room.
        request.timeoutInterval = depth == .deep ? 90 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anti-abuse tripwire, not real auth — see AppConfig.appSharedSecret.
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Secret")
        request.httpBody = try JSONEncoder.backend.encode(
            InsightRequest(
                stats: stats,
                persona: persona,
                locale: Locale.current.identifier,
                appUserId: appUserID,
                variationSeed: variationSeed,
                depth: depth == .deep ? depth.rawValue : nil,
                runId: runID.uuidString
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // Preserve cancellation so callers (and the fallback wrapper)
            // don't mistake a user-cancelled scan for a backend outage.
            throw CancellationError()
        } catch {
            throw AnalysisError.backendUnavailable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AnalysisError.backendUnavailable(underlying: nil)
        }

        let decoded: InsightResponse
        do {
            decoded = try JSONDecoder.backend.decode(InsightResponse.self, from: data)
        } catch {
            throw AnalysisError.backendUnavailable(underlying: error)
        }

        let (headline, body) = Self.splitHeadline(from: decoded.insightText, persona: persona)
        return Insight(
            id: UUID(),
            persona: persona,
            generatedAt: decoded.generatedAt,
            headline: headline,
            body: body,
            segments: decoded.segments,
            shareLine: decoded.shareLine,
            superlatives: stats.cardSuperlatives
        )
    }

    /// The backend's output contract puts a punchy title on the first line,
    /// then a blank line, then the narrative. Parse defensively — if the model
    /// ignored the format, fall back to a generic headline and keep all text.
    static func splitHeadline(from text: String, persona: Persona) -> (headline: String, body: String) {
        let fallbackHeadline = persona == .roast ? "Your Gallery, Roasted" : "Your Gallery, Read"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let newline = trimmed.firstIndex(of: "\n") else {
            return (fallbackHeadline, trimmed)
        }

        let headline = String(trimmed[..<newline])
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*\"'“” ").union(.whitespaces))
        let body = String(trimmed[newline...]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !headline.isEmpty, !body.isEmpty, headline.count <= 60 else {
            return (fallbackHeadline, trimmed)
        }
        return (headline, body)
    }
}

extension PhotoStats {
    /// Deterministic, stats-derived superlatives for the results grid and
    /// share card. Computed client-side so the numbers are always exact —
    /// the LLM only writes the narrative.
    var cardSuperlatives: [Insight.Superlative] {
        var items: [Insight.Superlative] = []

        if let top = topCategories.first {
            items.append(.init(title: "Top obsession", detail: "\(top.category) — \(top.count) photos"))
        }
        items.append(.init(title: "Selfie ratio", detail: "\(Int(selfieRatio * 100))% of everything"))
        if screenshotCount > 0 {
            items.append(.init(title: "Screenshot hoard", detail: "\(screenshotCount) and counting"))
        }
        if let peakHour = photosByHourOfDay.enumerated().max(by: { $0.element < $1.element })?.offset {
            items.append(.init(title: "Witching hour", detail: String(format: "%02d:00", peakHour)))
        }
        return items
    }
}

extension JSONEncoder {
    static let backend: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let backend: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
