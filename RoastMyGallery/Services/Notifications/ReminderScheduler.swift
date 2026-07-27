import Foundation
import UserNotifications

/// Re-engagement notifications: the monthly recap ritual, plus one nudge for
/// users who have drifted away. Both live behind the single Settings toggle.
///
/// WHY NOT A FIXED WEEKLY PING (what this replaced): the product's unit of
/// analysis is a month or an album — `PersonaPickerView.canStart` won't begin a
/// standard run without one — so "this week's photos are waiting" promised
/// something the app cannot actually scan. Worse, a generic weekly reminder
/// trains people to swipe it away, and on iOS a user who turns notifications
/// off is gone for good. Relevance, not cadence, is what survives: a
/// notification that names the month they can analyze *right now* has a real
/// reason to exist, so this schedules fewer and says more.
///
/// PERMISSION POLICY: authorization is requested lazily — only when the user
/// turns the reminder on — never at app launch. If they previously denied,
/// `enableReminder()` reports `.denied` so the caller can revert its toggle
/// and point them at iOS Settings.
///
/// APP STORE NOTE (Guideline 4.5.4): notifications may not be used for
/// advertising or promotion without separate in-app consent, so nothing here
/// mentions gem packs or prices. These drive *usage*; in a consumable economy
/// a spent balance produces the next purchase on its own.
enum ReminderScheduler {
    /// Identifier of the weekly reminder shipped in earlier builds. Still
    /// cleared on every refresh so an upgrading user doesn't keep receiving a
    /// reminder this version no longer schedules.
    private static let legacyWeeklyID = "monthly-rescan-reminder"

    private static let recapIDPrefix = "monthly-recap-"
    private static let lapsedID = "lapsed-nudge"

    /// Each recap names its own month, so they're scheduled as individual
    /// one-shots rather than one repeating trigger. Six keeps a user who opens
    /// the app twice a year covered, and is far under iOS's 64-pending limit.
    private static let recapMonthsAhead = 6

    /// Quiet-hours guard: everything fires late morning local time.
    private static let fireHour = 11

    /// Days of silence after a completed analysis before the drift nudge
    /// fires. Re-armed on every run, so an active user never receives one.
    private static let lapsedAfterDays = 14

    private static let lastAnalysisKey = "reminderLastAnalysisDate"
    /// Same key as `SettingsView`'s `@AppStorage` toggle — that switch is the
    /// single source of truth for whether any of this is scheduled.
    private static let enabledKey = "monthlyReminderEnabled"

    enum EnableResult {
        case scheduled
        case denied
    }

    /// Requests permission if it hasn't been decided yet, then builds the
    /// schedule. Returns `.denied` if notifications are turned off.
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

        await refresh()
        return .scheduled
    }

    /// Cancels everything this type schedules. Safe when nothing is pending.
    static func disableReminder() {
        clearAll(on: UNUserNotificationCenter.current())
    }

    /// Rebuilds the whole schedule from scratch. Safe to call as often as you
    /// like — it clears what it owns first, so requests can never stack. Call
    /// at launch: recaps are only scheduled six months out, and the drift
    /// nudge has to be pushed forward as the user keeps using the app.
    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        clearAll(on: center)

        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            // Permission revoked in iOS Settings since the toggle was flipped.
            return
        }

        await scheduleMonthlyRecaps(on: center)
        await scheduleLapsedNudge(on: center)
    }

    /// Record a completed analysis: pushes the drift nudge out so it only ever
    /// reaches someone who has actually stopped using the app.
    static func noteAnalysisCompleted() {
        UserDefaults.standard.set(Date.now, forKey: lastAnalysisKey)
        Task { await refresh() }
    }

    // MARK: - Monthly recap

    /// One notification on the 1st of each of the next `recapMonthsAhead`
    /// months, each naming the month that just ended — the month the user can
    /// pick in the scan flow that morning. This is the anchor: a predictable
    /// ritual tied to the exact slice of library the product analyzes.
    private static func scheduleMonthlyRecaps(on center: UNUserNotificationCenter) async {
        let calendar = Calendar.current
        guard let thisMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) else { return }

        for offset in 1...recapMonthsAhead {
            guard
                let fireMonth = calendar.date(byAdding: .month, value: offset, to: thisMonthStart),
                let fireDate = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: fireMonth),
                let recapMonth = calendar.date(byAdding: .month, value: -1, to: fireMonth)
            else { continue }

            let name = recapMonth.formatted(.dateTime.month(.wide))
            let content = UNMutableNotificationContent()
            content.title = "\(name) is a wrap"
            content.body = "See what your \(name) photos say about you."
            content.sound = .default

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: "\(recapIDPrefix)\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    // MARK: - Drift nudge

    /// A single reminder `lapsedAfterDays` after the last completed analysis.
    /// Deliberately not scheduled for someone who has never run one: Home's
    /// empty state is already asking, and a nudge before the user has seen
    /// what the app does is noise they'll answer by turning notifications off.
    private static func scheduleLapsedNudge(on center: UNUserNotificationCenter) async {
        guard let last = UserDefaults.standard.object(forKey: lastAnalysisKey) as? Date else { return }

        let calendar = Calendar.current
        guard
            let day = calendar.date(byAdding: .day, value: lapsedAfterDays, to: last),
            let fireDate = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day),
            // Already past — don't ambush someone who just opened the app.
            fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your camera roll has been busy"
        content.body = "It's been a couple of weeks. See what's changed since your last roast."
        content.sound = .default

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: lapsedID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: - Teardown

    private static func clearAll(on center: UNUserNotificationCenter) {
        var ids = [legacyWeeklyID, lapsedID]
        ids += (1...recapMonthsAhead).map { "\(recapIDPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
