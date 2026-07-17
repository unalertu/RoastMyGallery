import Foundation
import os

/// Thin client for the backend's gem-grant endpoint.
///
/// Why a backend hop at all: RevenueCat Virtual Currency balances can only be
/// *adjusted* with the RevenueCat **secret** key, which must never ship in the
/// app. So the app asks the backend; the backend calls RevenueCat. The paid
/// actions (analysis, Deep Vision) are deducted server-side inside their own
/// endpoints — the one-time starter grant is the only client-initiated
/// adjustment. Best-effort: a failure is logged and returns `false`, and the
/// caller simply retries on a later launch (see `ensureStarterGrant`).
enum GemBackendClient {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "RoastMyGallery",
        category: "Gems"
    )

    private struct GrantRequest: Encodable {
        let appUserId: String
    }

    /// Grant one-time starter gems to a newly seen App User ID.
    static func starterGrant(appUserID: String) async -> Bool {
        await post(path: "api/starter-grant", body: GrantRequest(appUserId: appUserID))
    }

    private static func post<Body: Encodable>(path: String, body: Body) async -> Bool {
        var request = URLRequest(url: AppConfig.backendBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Same anti-abuse tripwire as the insight endpoint.
        request.setValue(AppConfig.appSharedSecret, forHTTPHeaderField: "X-App-Secret")
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.warning("Gem request \(path, privacy: .public) rejected with status \(status)")
                return false
            }
            return true
        } catch {
            logger.warning("Gem request \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
