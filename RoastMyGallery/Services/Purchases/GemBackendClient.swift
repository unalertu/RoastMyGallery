import Foundation
import os

/// Thin client for the backend's gem-grant endpoint.
///
/// Why a backend hop at all: RevenueCat Virtual Currency balances can only be
/// *adjusted* with the RevenueCat **secret** key, which must never ship in the
/// app. So the app asks the backend; the backend calls RevenueCat. The paid
/// actions (analysis, Deep Vision) are deducted server-side inside their own
/// endpoints — the one-time starter grant is the only client-initiated
/// adjustment. Best-effort: a failure is logged and reported as `.unavailable`,
/// and the caller simply retries on a later launch (see `ensureStarterGrant`).
enum GemBackendClient {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RoastMyGallery",
        category: "Gems"
    )

    private struct GrantRequest: Encodable {
        let appUserId: String
    }

    /// Response contract of `backend/api/starter-grant.js`.
    private struct GrantResponse: Decodable {
        let ok: Bool
        let granted: Bool
        /// Present only when `granted` is false: "already_granted" (settled) or
        /// "not_configured" (nothing granted, nothing recorded — retryable).
        let reason: String?
    }

    /// What a starter-grant request actually accomplished.
    ///
    /// The distinction matters because HTTP 200 does NOT mean gems arrived: the
    /// backend fails open when its RevenueCat env vars are missing and answers
    /// 200 with `granted: false`. Treating that as success is what would let a
    /// user latch "already asked" while sitting at a zero balance forever.
    enum StarterGrantOutcome {
        /// Gems were added to the balance.
        case granted
        /// The server confirms this App User ID already had its starter gems.
        /// Settled — never ask again.
        case alreadyGranted
        /// Nothing was granted and nothing was recorded server-side (backend
        /// misconfigured, unreachable, or the request was rejected). The caller
        /// must leave its "asked" flag unset and retry on a later launch.
        case unavailable
    }

    /// Grant one-time starter gems to a newly seen App User ID.
    static func starterGrant(appUserID: String) async -> StarterGrantOutcome {
        guard let data = await post(path: "api/starter-grant", body: GrantRequest(appUserId: appUserID)) else {
            return .unavailable
        }
        guard let decoded = try? JSONDecoder().decode(GrantResponse.self, from: data), decoded.ok else {
            logger.warning("Starter grant returned an unreadable body — treating as retryable.")
            return .unavailable
        }
        if decoded.granted { return .granted }
        // Only a server-confirmed prior grant settles this. Anything else
        // (notably "not_configured") stays retryable on purpose.
        if decoded.reason == "already_granted" { return .alreadyGranted }
        logger.warning("Starter grant not applied (reason: \(decoded.reason ?? "unspecified", privacy: .public)) — will retry.")
        return .unavailable
    }

    /// POSTs `body` and returns the response data on a 2xx, or nil on any
    /// transport/status failure (logged).
    private static func post<Body: Encodable>(path: String, body: Body) async -> Data? {
        var request = URLRequest(url: AppConfig.backendBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Same anti-abuse tripwire as the insight endpoint.
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Secret")
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("Gem request \(path, privacy: .public) rejected with status \(status)")
                return nil
            }
            return data
        } catch {
            logger.warning("Gem request \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
