import SwiftUI
import StoreKit
import UIKit

/// Tab 3 — Plan, Privacy, Preferences, Data, About. Custom pastel sections
/// (not Form) so it matches the design system.
struct SettingsView: View {
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false

    /// Populated after a restore attempt to drive the result alert.
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    /// Shown when the user enables the reminder but notifications are off.
    @State private var showNotificationDeniedAlert = false

    /// Drives the monthly reminder. Persisted so the row reflects the user's
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
                        privacySection
                        preferencesSection
                        dataSection
                        aboutSection
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
                history.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved analysis from this device. It can't be undone.")
        }
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
        .alert("Notifications are off", isPresented: $showNotificationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To get a monthly re-scan reminder, turn on notifications for Roast My Gallery in iOS Settings.")
        }
        .onChange(of: monthlyReminderEnabled) { _, enabled in
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
                    Text("Credits")
                        .font(Theme.Typography.headline)
                    Text(purchaseManager.isSubscribed
                         ? "Subscribed — \(PurchaseManager.advertisedCredits(forProductID: PurchaseManager.ProductID.monthly.rawValue) ?? 50) credits top up monthly"
                         : "\(PurchaseManager.analysisCost) credit per analysis · \(PurchaseManager.deepVisionCost) per Deep Vision batch")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Text("\(purchaseManager.creditBalance)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.Colors.accentSoft, in: Capsule())
            }

            if purchaseManager.isSubscribed {
                Text("Subscribed · renews monthly")
                    .font(Theme.Typography.label)
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Divider().overlay(Theme.Colors.background)
            Button(purchaseManager.isSubscribed ? "Get more credits" : "Get credits") { showPaywall = true }
                .buttonStyle(SoftButtonStyle())

            Divider().overlay(Theme.Colors.background)
            Button {
                Task {
                    isRestoring = true
                    defer { isRestoring = false }
                    restoreMessage = message(for: await purchaseManager.restorePurchases())
                }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    if isRestoring { ProgressView() }
                    Text(isRestoring ? "Restoring…" : "Restore Purchases")
                }
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.s)
            }
            .disabled(isRestoring)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                Text("Your photos are analyzed entirely on this device and never leave it. The only exception: Deep Analysis photos you hand-pick and explicitly approve, batch by batch.")
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
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        SettingsSection(title: "Preferences") {
            Toggle(isOn: $monthlyReminderEnabled) {
                SettingsRowLabel(
                    icon: "bell",
                    title: "Monthly re-scan reminder",
                    detail: "A gentle nudge when there's fresh material"
                )
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
            Button {
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
                // System review prompt. Apple rate-limits how often this
                // actually appears (a few times per year), so tapping may show
                // nothing — that's expected, not a bug.
                // TODO: once the app is published, add the real App Store ID so
                // we can offer an "open App Store to review" fallback for users
                // who've already used up their prompt quota.
                requestReview()
            } label: {
                SettingsRowLabel(icon: "star", title: "Rate this app", detail: nil)
            }
            .buttonStyle(.plain)
        }
    }

    /// `mailto:` URL pre-filled with a support address plus app/device context,
    /// so feedback arrives with the info we'd otherwise have to ask for.
    private var feedbackMailURL: URL? {
        // TODO: swap for the real support address before shipping.
        let supportAddress = "support@example.com"
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

    private func message(for result: PurchaseManager.RestoreResult) -> String {
        switch result {
        case .restoredSubscription:
            return "Your subscription has been restored. Monthly credits will keep topping up."
        case .noPurchases:
            return "No subscription was found on this Apple ID. (Consumable credit packs can't be restored — see support.)"
        case .failed(let reason):
            return reason
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Section & row building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title.uppercased())
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.textSecondary)
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
