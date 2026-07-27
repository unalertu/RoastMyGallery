import Photos
import SwiftUI
import UIKit
import UserNotifications

/// Tab 3 — Plan, Preferences, Data, About, Privacy, then the delete-history
/// row on its own at the foot. Custom pastel sections (not Form) so it matches
/// the design system.
struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Mirrors the system photo permission. Re-read whenever the app becomes
    /// active, because the only way to change it is a round trip to iOS
    /// Settings — granting or narrowing access there has to be reflected here
    /// when the user comes back. (Revoking outright terminates the app, so
    /// that case takes care of itself.)
    @State private var photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    /// Mirrors the system notification permission, for the same reason
    /// `photoAccess` does: once it's been decided, iOS Settings is the only
    /// place it changes, so it has to be re-read on every activation.
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Set when the user flips the notification switch on while permission is
    /// denied — we send them to iOS Settings, and if they come back with it
    /// granted we finish the job they asked for instead of making them tap twice.
    @State private var resumeNotificationsAfterSettings = false

    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false

    /// Outcome of a Restore tap, success or failure. A restore that finishes
    /// with no visible result reads as a broken button, which is worse than
    /// not having one — so this always says something.
    @State private var restoreMessage: String?

    /// Flips the User ID row's subtitle to a confirmation for a beat after a
    /// copy. A pasteboard write is otherwise completely invisible.
    @State private var didCopyUserID = false

    /// Whether this app's notifications are scheduled. Persisted, but it is
    /// only half the story — the switch below shows this AND the system
    /// permission, since either one being off means nothing arrives.
    @AppStorage("monthlyReminderEnabled") private var monthlyReminderEnabled = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.l) {
                        planSection
                        preferencesSection
                        dataSection
                        aboutSection
                        privacySection
                        // Last thing on the page, on its own: the one action
                        // here that destroys something.
                        deleteHistorySection
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        }
        .tint(Theme.Colors.accent)
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            Task {
                await refreshNotificationStatus()
                // Came back from iOS Settings having granted permission —
                // turn on what they were reaching for in the first place.
                if resumeNotificationsAfterSettings, notificationStatus.allowsScheduling {
                    resumeNotificationsAfterSettings = false
                    monthlyReminderEnabled = true
                    // Not just the flag: it may already have been true (they
                    // revoked permission in iOS Settings while it was on), and
                    // `.onChange` doesn't fire on a write that changes nothing.
                    // Scheduling twice is a no-op — `refresh()` rebuilds from
                    // fixed identifiers — so the overlap is safe.
                    _ = await ReminderScheduler.enableReminder()
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert(
            "Restore Purchases",
            isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .confirmationDialog(
            "Delete all analysis history?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All History", role: .destructive) {
                Haptics.warning()
                history.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved analysis from this device. It can't be undone.")
        }
        .onChange(of: monthlyReminderEnabled) { _, enabled in
            guard enabled else {
                ReminderScheduler.disableReminder()
                return
            }
            Task {
                // Requests permission on the way in if it has never been asked.
                let result = await ReminderScheduler.enableReminder()
                if result == .denied {
                    // They said no to the system prompt just now. Snap back
                    // and let the row explain itself — following a fresh "no"
                    // with an alert asking again is how you lose the second ask.
                    monthlyReminderEnabled = false
                }
                await refreshNotificationStatus()
            }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        SettingsSection(title: "Plan") {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Gems")
                        .font(Theme.Typography.headline)
                    Text("\(PurchaseManager.analysisCost) gem per analysis · \(PurchaseManager.deepAnalysisCost) per Deep Analysis")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("\(purchaseManager.gemBalance)")
                        .font(Theme.Typography.title)
                }
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Colors.accentSoft, in: Capsule())
            }

            Divider().overlay(Theme.Colors.background)
            Button("Get gems") {
                Haptics.tap()
                showPaywall = true
            }
            .buttonStyle(SoftButtonStyle())

            Divider().overlay(Theme.Colors.background)

            // Restore also sits in the paywall footer, where Guideline 3.1.1
            // strictly requires it. It's duplicated here because that is where
            // both App Review and a user who just reinstalled go looking for
            // it, and neither should have to open a purchase screen to find it.
            Button {
                Haptics.tap()
                Task { await restore() }
            } label: {
                HStack {
                    SettingsRowLabel(
                        icon: "arrow.clockwise",
                        title: "Restore Purchases",
                        detail: "Re-sync gems bought with this Apple Account"
                    )
                    Spacer()
                    if purchaseManager.restoreInFlight {
                        ProgressView().tint(Theme.Colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(purchaseManager.restoreInFlight)
        }
    }

    /// `@MainActor` because `PurchaseManager` is — reading the balance and
    /// clearing `lastError` are cross-actor accesses without it.
    @MainActor
    private func restore() async {
        await purchaseManager.restorePurchases()
        // Consume the error rather than leaving it set: the paywall renders
        // `lastError` as a banner, and a failure already reported here should
        // not greet the user again the next time they open it.
        if let error = purchaseManager.lastError {
            restoreMessage = error
            purchaseManager.lastError = nil
        } else {
            let balance = purchaseManager.gemBalance
            restoreMessage = "Your purchases are up to date. You have \(balance) \(balance == 1 ? "gem" : "gems")."
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                Text("Your photos are analyzed on this device, and by default only anonymous statistics are sent. A photo leaves your phone only if you turn on AI captions — and even then you see the exact photos and approve them first. Approved photos go to our AI provider, Google Gemini, to be captioned — they are not used to train any AI model, and we don't keep a copy.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

            Divider().overlay(Theme.Colors.background)

            // Photo access is the one permission the app cannot work without,
            // and the two failure modes are invisible from inside the app:
            // `.limited` silently hides every album, and `.denied` makes each
            // analysis fail at the last step. Surfacing the state here — with
            // a jump to the iOS Settings page that changes it — turns both
            // into something the user can see and fix.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                SettingsRowLabel(
                    icon: photoAccess.iconName,
                    title: "Photo Access",
                    detail: photoAccess.settingsDetail,
                    tint: photoAccess.needsAttention ? Theme.Colors.danger : Theme.Colors.textPrimary
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.Colors.background)

            NavigationLink {
                DataTransparencyView()
            } label: {
                SettingsRowLabel(
                    icon: "doc.text.magnifyingglass",
                    title: "Review what data was sent",
                    detail: "See the exact statistics used for your insight"
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.Colors.background)

            Button {
                openURL(AppConfig.privacyPolicyURL)
            } label: {
                SettingsRowLabel(
                    icon: "hand.raised",
                    title: "Privacy Policy",
                    detail: "How we handle your data"
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.Colors.background)

            Button {
                openURL(AppConfig.termsOfUseURL)
            } label: {
                SettingsRowLabel(
                    icon: "doc.plaintext",
                    title: "Terms of Use",
                    detail: "The terms you agree to by using the app"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        // One row for now. The Appearance row that used to sit here was a dimmed
        // "SOON" teaser for the unbuilt dark theme — placeholder UI under App
        // Store Review Guideline 2.1 — so it's gone until there's a real theme
        // to switch to (the app forces Light Mode at the root meanwhile).
        SettingsSection(title: "Preferences") {
            Toggle(isOn: notificationsEnabled) {
                SettingsRowLabel(
                    icon: notificationStatus.allowsScheduling ? "bell" : "bell.slash",
                    title: "Notifications",
                    detail: notificationsDetail,
                    tint: notificationStatus == .denied
                        ? Theme.Colors.danger
                        : Theme.Colors.textPrimary
                )
            }
            .tint(Theme.Colors.accent)
        }
    }

    /// The switch reads the *effective* state — our schedule AND the system
    /// permission — because a row showing "on" while iOS is dropping every
    /// notification is just a lie the user discovers weeks later.
    ///
    /// Turning it on when permission was denied can't be done from in here at
    /// all, so that tap goes straight to iOS Settings rather than bouncing off
    /// an alert first; `resumeNotificationsAfterSettings` finishes the job on
    /// the way back.
    private var notificationsEnabled: Binding<Bool> {
        Binding(
            get: { monthlyReminderEnabled && notificationStatus.allowsScheduling },
            set: { wantsOn in
                Haptics.selection()
                guard wantsOn else {
                    monthlyReminderEnabled = false
                    return
                }
                if notificationStatus == .denied {
                    resumeNotificationsAfterSettings = true
                    openSystemSettings()
                } else {
                    monthlyReminderEnabled = true
                }
            }
        )
    }

    /// Names what actually arrives — a switch labelled only "Notifications"
    /// asks people to opt into an unknown — and says where to fix it when the
    /// answer isn't in this app.
    /// No `.restricted` case here, unlike the photo permission below:
    /// `UNAuthorizationStatus` has no such member. Its cases are
    /// `.notDetermined`, `.denied`, `.authorized`, `.provisional` and
    /// `.ephemeral` — a device-level block surfaces as `.denied`, which the
    /// first case already covers.
    private var notificationsDetail: String {
        switch notificationStatus {
        case .denied:
            return "Turned off in iOS Settings — tap to turn them back on"
        default:
            return "A monthly recap when a new month is ready, and a nudge if you drift away"
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        SettingsSection(title: "Data") {
            NavigationLink {
                GalleryStatsView()
            } label: {
                SettingsRowLabel(
                    icon: "chart.bar.xaxis.ascending",
                    title: "Gallery Stats",
                    detail: "Selfies, animals, categories & more"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Delete history

    /// Sits alone at the very bottom, headerless: the standard iOS place for
    /// the one irreversible action on a settings screen, far from anything a
    /// user is scrolling *to*.
    private var deleteHistorySection: some View {
        SettingsSection(title: nil) {
            Button {
                Haptics.tap()
                showDeleteConfirmation = true
            } label: {
                SettingsRowLabel(
                    icon: "trash",
                    title: "Delete all analysis history",
                    detail: history.records.isEmpty
                        ? "Nothing saved yet"
                        : "\(history.records.count) saved \(history.records.count == 1 ? "analysis" : "analyses")",
                    tint: Theme.Colors.danger
                )
            }
            .buttonStyle(.plain)
            .disabled(history.records.isEmpty)
            .opacity(history.records.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            HStack {
                SettingsRowLabel(icon: "app.badge", title: "Version", detail: nil)
                Spacer()
                Text(SupportMail.appVersion)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Divider().overlay(Theme.Colors.background)

            Button {
                // The support page, not a `mailto:` draft: it answers the
                // common questions (missing gems, new phone, refunds) before
                // anyone needs to write in, and it still carries the address
                // for those who do — including users with no mail account set
                // up, for whom a `mailto:` row does nothing at all.
                openURL(AppConfig.supportURL)
            } label: {
                SettingsRowLabel(
                    icon: "lifepreserver",
                    title: "Contact & Feedback",
                    detail: "Help, common questions and our email"
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.Colors.background)

            Button {
                // Deliberately NOT `requestReview()` here: Apple throttles the
                // in-app sheet (~3/year) and silently shows nothing beyond
                // that, which makes a tapped button feel broken. An explicit
                // tap deep-links straight to the App Store review form
                // instead — always works. The automatic in-app ask lives in
                // ReviewPrompter/ScanFlowView.
                if let url = URL(string: "\(Self.appStoreURL)?action=write-review") {
                    openURL(url)
                }
            } label: {
                SettingsRowLabel(icon: "star", title: "Rate this app", detail: nil)
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.Colors.background)

            Button {
                showShareSheet = true
            } label: {
                SettingsRowLabel(icon: "square.and.arrow.up", title: "Share this app", detail: nil)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showShareSheet) {
                let appURL = URL(string: Self.appStoreURL)!
                ShareSheet(items: [
                    "Check out Roast My Gallery — it hilariously roasts your camera roll! 📸🔥",
                    appURL
                ])
                .presentationDetents([.medium])
            }

            Divider().overlay(Theme.Colors.background)

            // Last row in the section on purpose. It is the only string that
            // identifies this customer to us — without it a "my gems are gone"
            // email is unanswerable, since there is no account and no address
            // to look them up by — but it is support plumbing, not something
            // anyone opens Settings to read, so it sits below the rows people
            // actually come here for. Middle-truncated because it exists to be
            // copied, not read.
            Button {
                UIPasteboard.general.string = purchaseManager.appUserID
                Haptics.success()
                didCopyUserID = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    didCopyUserID = false
                }
            } label: {
                HStack {
                    SettingsRowLabel(
                        icon: "person.text.rectangle",
                        title: "User ID",
                        detail: didCopyUserID ? "Copied to clipboard" : "Tap to copy — include it when you contact support"
                    )
                    Spacer(minLength: Theme.Spacing.m)
                    Text(purchaseManager.appUserID)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - URLs
    /// App Store product page (Apple ID 6791121107) — used by both the
    /// share sheet and, with `?action=write-review`, the Rate button.
    private static let appStoreURL = "https://apps.apple.com/app/roast-my-gallery/id6791121107"
    // Privacy / Terms links live in `AppConfig` — one place for all four
    // surfaces that link them.
}

// MARK: - Section & row building blocks

private struct SettingsSection<Content: View>: View {
    /// `nil` for a card that stands on its own — the trailing delete row has
    /// nothing to group with and no header worth reading.
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Same section-header language as Home's "New Analysis" /
            // "Earlier Analysis" — one pattern across tabs.
            if let title {
                Text(title)
                    .font(Theme.Typography.headline)
                    .padding(.leading, Theme.Spacing.xs)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
    }
}

private struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let detail: String?
    var tint: Color = Theme.Colors.textPrimary

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(tint == Theme.Colors.textPrimary ? Theme.Colors.accent : tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(tint)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Notification permission presentation

private extension UNAuthorizationStatus {
    /// True when iOS will actually deliver what we schedule. `.notDetermined`
    /// counts: nothing is blocked yet, and flipping the switch is what triggers
    /// the system prompt (see `ReminderScheduler`'s lazy permission policy).
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral, .notDetermined: return true
        default: return false
        }
    }
}

// MARK: - Photo permission presentation

private extension PHAuthorizationStatus {
    /// True when the current state stops the app doing its job, or quietly
    /// narrows what it can see — the two cases worth colouring red.
    var needsAttention: Bool {
        switch self {
        case .denied, .restricted, .limited: return true
        default: return false
        }
    }

    var iconName: String {
        switch self {
        case .authorized: return "photo.on.rectangle"
        case .limited: return "photo.badge.exclamationmark"
        case .denied, .restricted: return "exclamationmark.triangle"
        default: return "photo.on.rectangle"
        }
    }

    /// Says what the current state *costs the user*, not just what it is —
    /// "Limited" on its own doesn't explain why their albums vanished.
    ///
    /// `nil` when access is full: there is nothing to fix and nothing to warn
    /// about, so the row stays a bare title rather than reassuring the user
    /// about something they never asked about.
    var settingsDetail: String? {
        switch self {
        case .authorized:
            return nil
        case .limited:
            return "Limited — only the photos you picked. Albums stay hidden; tap to allow Full Access"
        case .denied:
            return "Off — analyses can't run. Tap to turn photo access back on"
        case .restricted:
            return "Blocked by this device's restrictions (Screen Time or a profile)"
        case .notDetermined:
            return "Not set yet — you'll be asked when you run your first analysis"
        @unknown default:
            return "Tap to review photo access in iOS Settings"
        }
    }
}

// MARK: - UIKit Share Sheet wrapper

/// Minimal `UIActivityViewController` wrapper for SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
