import Photos
import SwiftUI
import UIKit

/// Tab 3 — Plan, Preferences, Data, About, Privacy. Custom pastel sections
/// (not Form) so it matches the design system.
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

    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false

    /// Shown when the user enables the reminder but notifications are off.
    @State private var showNotificationDeniedAlert = false

    /// Drives the weekly reminder. Persisted so the row reflects the user's
    /// choice, but the actual scheduling happens in `.onChange` below via
    /// `ReminderScheduler` (which requests permission lazily, only here).
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            photoAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
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
        .alert("Notifications are off", isPresented: $showNotificationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To get a weekly re-scan reminder, turn on notifications for Roast My Gallery in iOS Settings.")
        }
        .onChange(of: monthlyReminderEnabled) { _, enabled in
            Haptics.selection()
            if enabled {
                Task {
                    let result = await ReminderScheduler.enableReminder()
                    if result == .denied {
                        // Permission unavailable — undo the toggle and explain.
                        monthlyReminderEnabled = false
                        showNotificationDeniedAlert = true
                    }
                }
            } else {
                ReminderScheduler.disableReminder()
            }
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
            Toggle(isOn: $monthlyReminderEnabled) {
                SettingsRowLabel(icon: "bell", title: "Notifications", detail: nil)
            }
            .tint(Theme.Colors.accent)
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

            Divider().overlay(Theme.Colors.background)

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
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            // Same section-header language as Home's "New Analysis" /
            // "Earlier Analysis" — one pattern across tabs.
            Text(title)
                .font(Theme.Typography.headline)
                .padding(.leading, Theme.Spacing.xs)

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
