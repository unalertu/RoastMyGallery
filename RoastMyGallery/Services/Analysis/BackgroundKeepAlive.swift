import UIKit

/// Holds a UIKit background-task assertion for the lifetime of one analysis
/// run (scan pipeline or Deep Vision batch), buying ~30 seconds of extra
/// runtime if the user backgrounds the app mid-run — enough for a typical
/// backend call to land (and be charged exactly once) instead of dying in
/// flight. If iOS calls time first, the assertion is released and the run
/// simply suspends with the app: on return it either completed or surfaces
/// the normal failure path. Because the backend charges deduct-after-success
/// (idempotent per runID), a run that never finishes never charges — this
/// class only ever helps a single charge complete.
@MainActor
final class BackgroundKeepAlive {
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}
