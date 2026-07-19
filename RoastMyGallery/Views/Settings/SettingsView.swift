import SwiftUI
import UIKit

/// Tab 3 — Plan, Preferences, Data, About, Privacy. Custom pastel sections
/// (not Form) so it matches the design system.
struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(\.openURL) private var openURL

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
                Text("Your photos are analyzed on this device, and by default only anonymous statistics are sent. Photos leave your phone only when you opt in — the AI captions and Deep Vision you approve, batch by batch — and they're never stored on the server.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(3)
            }

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
                if let url = URL(string: Self.privacyPolicyURL) {
                    openURL(url)
                }
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
                if let url = URL(string: Self.termsOfUseURL) {
                    openURL(url)
                }
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
        SettingsSection(title: "Preferences") {
            Toggle(isOn: $monthlyReminderEnabled) {
                SettingsRowLabel(icon: "bell", title: "Notifications", detail: nil)
            }
            .tint(Theme.Colors.accent)

            Divider().overlay(Theme.Colors.background)

            // Non-interactive on purpose: the DesignSystem palette is tuned for
            // light backgrounds only and the app forces Light Mode at the root,
            // so there's nothing to switch to yet. Rendered dimmed with a
            // "Soon" tag so it doesn't read as a tappable control.
            HStack {
                SettingsRowLabel(
                    icon: "sun.max",
                    title: "Appearance",
                    detail: "Light — a dark pastel theme is on the way"
                )
                Spacer()
                Text("SOON")
                    .font(Theme.Typography.label)
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.cream, in: Capsule())
            }
            .opacity(0.55)
            .allowsHitTesting(false)
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
                Text(appVersion)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Divider().overlay(Theme.Colors.background)

            Button {
                if let url = feedbackMailURL { openURL(url) }
            } label: {
                SettingsRowLabel(icon: "envelope", title: "Contact & Feedback", detail: nil)
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

    /// `mailto:` URL pre-filled with a support address plus app/device context,
    /// so feedback arrives with the info we'd otherwise have to ask for.
    private var feedbackMailURL: URL? {
        let supportAddress = "roastmygallery@gmail.com"
        let body = """


        —
        Please write your feedback above this line.
        App version: \(appVersion)
        Device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Roast My Gallery feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    // MARK: - URLs
    /// App Store product page (Apple ID 6791121107) — used by both the
    /// share sheet and, with `?action=write-review`, the Rate button.
    private static let appStoreURL = "https://apps.apple.com/app/roast-my-gallery/id6791121107"
    private static let privacyPolicyURL = "https://roastmygallery.unlertu.workers.dev/privacy/"
    private static let termsOfUseURL = "https://roastmygallery.unlertu.workers.dev/terms/"
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

// MARK: - UIKit Share Sheet wrapper

/// Minimal `UIActivityViewController` wrapper for SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
