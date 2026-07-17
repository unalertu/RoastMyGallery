import Foundation

/// Thin client for the two gem-mutation endpoints on our Vercel backend.
///
/// Why a backend hop at all: RevenueCat Virtual Currency balances can only be
/// *adjusted* with the RevenueCat **secret** key, which must never ship in the
/// app. So the app asks the backend to spend/grant; the backend calls
/// RevenueCat. See `backend/api/spend.js` and `backend/api/starter-grant.js`.
///
/// These are best-effort: a failure returns `false` (logged), and the caller
/// decides what to do. Spends are only issued *after* the paid action already
/// succeeded, so a failed deduction never blocks the user — it just means a
/// gem wasn't taken (logged server-side for reconciliation).
enum GemBackendClient {
    private struct SpendRequest: Encodable {
        let appUserId: String
        let amount: Int
        let reason: String
    }

    private struct GrantRequest: Encodable {
        let appUserId: String
    }

    /// Deduct `amount` gems for `reason` (e.g. "deep_vision").
    static func spend(appUserID: String, amount: Int, reason: String) async -> Bool {
        await post(path: "api/spend", body: SpendRequest(appUserId: appUserID, amount: amount, reason: reason))
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
                return false
            }
            return true
        } catch {
            // TODO: route through a proper logger.
            return false
        }
    }
}
