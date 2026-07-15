import Foundation
import UserNotifications

/// The single local notification the app schedules: a monthly nudge to re-scan
/// the gallery.
///
/// PERMISSION POLICY: authorization is requested lazily — only the first time
/// the user turns the reminder on — never at app launch. If the user has
/// previously denied notifications, `enableReminder()` reports `.denied` so the
/// caller can revert its toggle and point the user at iOS Settings.
enum ReminderScheduler {
    /// Stable identifier so we only ever have one pending reminder request.
    static let reminderID = "monthly-rescan-reminder"

    enum EnableResult {
        case scheduled
        case denied
    }

    /// Requests permission if it hasn't been decided yet, then schedules the
    /// repeating reminder. Returns `.denied` if notifications are turned off.
    static func enableReminder() async -> EnableResult {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return .denied }
        case .denied:
            return .denied
        default:
            // authorized, provisional, ephemeral — good to schedule.
            break
        }

        await schedule(on: center)
        return .scheduled
    }

    /// Cancels the pending reminder. Safe to call when nothing is scheduled.
    static func disableReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    private static func schedule(on center: UNUserNotificationCenter) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to re-scan"
        content.body = "A fresh month of photos is waiting to be roasted. See what changed."
        content.sound = .default

        // Fires on the 1st of every month at 11:00 local time. `repeats: true`
        // with a partial DateComponents set gives a recurring monthly trigger.
        var components = DateComponents()
        components.day = 1
        components.hour = 11
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger)

        // Replace any existing pending request so we never stack duplicates.
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        try? await center.add(request)
    }
}
