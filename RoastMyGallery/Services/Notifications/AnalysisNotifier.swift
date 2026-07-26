import Foundation
import UIKit
import UserNotifications

/// Local notifications for analysis runs that finish while the app is in the
/// background — used by both long-running flows (the scan pipeline and the
/// hand-picked Deep Vision batch). Follows the same permission policy as
/// `ReminderScheduler`: authorization is requested lazily — the first time
/// the user minimizes a running analysis — never at launch. If notifications
/// were denied, everything here degrades to silence; the in-app status banner
/// still covers the user when they return.
@MainActor
enum AnalysisNotifier {
    /// Which long-running flow a notification belongs to, so a tap can be
    /// routed back to the right surface (see `NotificationRouter`).
    enum Flow: String {
        case scan
        case deepVision
    }

    /// One stable identifier per flow: a newer completion replaces an unseen
    /// older one of the same flow instead of stacking, while a scan and a
    /// deep-vision completion can coexist.
    static func notificationID(for flow: Flow) -> String {
        "analysis-run-finished-\(flow.rawValue)"
    }

    // `nonisolated` because `NotificationRouter` — a plain NSObject, not on the
    // main actor — reads these from its async delegate callbacks. They're
    // immutable string literals, so there is nothing for the actor to protect;
    // without this the reads are a warning today and a hard error under the
    // Swift 6 language mode. Same reasoning as `PurchaseManager`'s constants.

    /// userInfo key carrying the finished record's UUID for tap routing.
    nonisolated static let recordIDKey = "recordID"
    /// userInfo key carrying the `Flow` raw value.
    nonisolated static let flowKey = "flow"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Posts "your analysis is ready" — but only when the app is actually in
    /// the background; in the foreground the status banner is the messenger.
    static func notifyCompletionIfBackgrounded(_ record: AnalysisRecord, flow: Flow = .scan) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = flow == .deepVision ? "Your Deep Vision results are ready" : "Your analysis is ready"
        content.body = record.insight.headline
        content.sound = .default
        content.userInfo = [recordIDKey: record.id.uuidString, flowKey: flow.rawValue]
        deliver(content, flow: flow)
    }

    static func notifyFailureIfBackgrounded(flow: Flow = .scan) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = flow == .deepVision ? "Deep Vision didn't finish" : "Analysis didn't finish"
        content.body = "Something went wrong along the way. Open the app to try again."
        content.sound = .default
        content.userInfo = [flowKey: flow.rawValue]
        deliver(content, flow: flow)
    }

    /// Once the user has seen (or dismissed) one flow's outcome in-app, take
    /// that ping back out of Notification Center so it can't route them to
    /// old news — without touching the other flow's pending notification.
    static func clearDelivered(for flow: Flow) {
        let ids = [notificationID(for: flow)]
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func deliver(_ content: UNNotificationContent, flow: Flow) {
        // nil trigger = deliver immediately. Without granted permission the
        // add is silently dropped, which is the intended degradation.
        let request = UNNotificationRequest(
            identifier: notificationID(for: flow),
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}

/// Routes completion-notification taps back into the app. `RoastMyGalleryApp`
/// registers the singleton as the notification-center delegate at launch (it
/// must be in place before launch finishes so a tap that cold-starts the app
/// is still delivered) and points `openAnalysis` at the app-scoped models.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Called on the main actor with the tapped record's ID (nil for failure
    /// notifications, which carry no record) and the flow it belongs to.
    var openAnalysis: (@MainActor (UUID?, AnalysisNotifier.Flow) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let flow = (userInfo[AnalysisNotifier.flowKey] as? String)
            .flatMap(AnalysisNotifier.Flow.init) else { return }
        let id = (userInfo[AnalysisNotifier.recordIDKey] as? String).flatMap(UUID.init)
        await MainActor.run { openAnalysis?(id, flow) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Analysis completions are never posted while active (see the
        // applicationState guards above), and if one slipped through the
        // in-app banner already covers it — show nothing. Other notifications
        // (the monthly reminder) keep their normal banner.
        let isAnalysis = notification.request.content
            .userInfo[AnalysisNotifier.flowKey] is String
        return isAnalysis ? [] : [.banner, .sound]
    }
}
