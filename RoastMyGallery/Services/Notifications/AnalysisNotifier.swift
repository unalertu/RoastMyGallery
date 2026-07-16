import Foundation
import UIKit
import UserNotifications

/// Local notifications for analysis runs that finish while the app is in the
/// background. Follows the same permission policy as `ReminderScheduler`:
/// authorization is requested lazily — the first time the user minimizes a
/// running analysis — never at launch. If notifications were denied,
/// everything here degrades to silence; the in-app status banner still covers
/// the user when they return.
@MainActor
enum AnalysisNotifier {
    /// One stable identifier: a newer completion replaces an unseen older one
    /// instead of stacking in Notification Center.
    static let notificationID = "analysis-run-finished"
    /// userInfo key carrying the finished record's UUID for tap routing.
    static let recordIDKey = "recordID"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Posts "your analysis is ready" — but only when the app is actually in
    /// the background; in the foreground the status banner is the messenger.
    static func notifyCompletionIfBackgrounded(_ record: AnalysisRecord) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your analysis is ready"
        content.body = record.insight.headline
        content.sound = .default
        content.userInfo = [recordIDKey: record.id.uuidString]
        deliver(content)
    }

    static func notifyFailureIfBackgrounded() {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Analysis didn't finish"
        content.body = "Something went wrong along the way. Open the app to try again."
        content.sound = .default
        deliver(content)
    }

    /// Once the user has seen (or dismissed) the outcome in-app, take the ping
    /// back out of Notification Center so it can't route them to old news.
    static func clearDelivered() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    private static func deliver(_ content: UNNotificationContent) {
        // nil trigger = deliver immediately. Without granted permission the
        // add is silently dropped, which is the intended degradation.
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}

/// Routes completion-notification taps back into the app. `RoastMyGalleryApp`
/// registers the singleton as the notification-center delegate at launch (it
/// must be in place before launch finishes so a tap that cold-starts the app
/// is still delivered) and points `openAnalysis` at the shared ScanViewModel.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Called on the main actor with the tapped record's ID (nil if missing).
    var openAnalysis: (@MainActor (UUID?) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == AnalysisNotifier.notificationID else { return }
        let id = (response.notification.request.content.userInfo[AnalysisNotifier.recordIDKey] as? String)
            .flatMap(UUID.init)
        await MainActor.run { openAnalysis?(id) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Analysis completions are never posted while active (see the
        // applicationState guards above), and if one slipped through the
        // in-app banner already covers it — show nothing. Other notifications
        // (the monthly reminder) keep their normal banner.
        notification.request.identifier == AnalysisNotifier.notificationID ? [] : [.banner, .sound]
    }
}
