import Foundation

/// Decides when to fire the system App Store rating prompt automatically.
///
/// Policy: ask only at the delight moment (the user is looking at a freshly
/// completed analysis), only after they've completed a couple of runs (so
/// first-run users aren't interrupted), and at most once per app version.
/// Apple additionally throttles the real sheet to ~3 displays per year, so
/// `requestReview()` beyond that is a silent no-op — the version gate here
/// just keeps us from burning that quota on one release.
///
/// The Settings "Rate this app" row stays independent of this: a manual tap
/// always calls `requestReview()` directly.
enum ReviewPrompter {
    private static let completedRunsKey = "reviewPromptCompletedRuns"
    private static let promptedVersionKey = "reviewPromptLastVersion"
    /// Don't ask before the user has seen this many successful analyses.
    private static let minimumCompletedRuns = 2

    /// Call once per successfully completed (paid) analysis run — counting
    /// lives in the view model so cache re-opens never inflate it.
    static func recordCompletedRun() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: completedRunsKey) + 1, forKey: completedRunsKey)
    }

    /// True when the results screen should request the review prompt now.
    /// Marks the current version as prompted when returning true, so each
    /// version asks at most once regardless of whether Apple shows the sheet.
    static func shouldPromptNow() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: completedRunsKey) >= minimumCompletedRuns else {
            return false
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
        guard defaults.string(forKey: promptedVersionKey) != version else { return false }
        defaults.set(version, forKey: promptedVersionKey)
        return true
    }
}
