import SwiftUI

/// A versioned, explicit permission for sending gallery-derived statistics to
/// a third-party AI service. A new key is intentional: existing installs must
/// see the disclosure before the first request made by this version.
enum AIDataSharingConsent {
    static let defaultsKey = "aiDataSharingConsent.v1"

    static var isGranted: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func grant() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    static func revoke() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
    }
}

/// Shown before the first Standard or Deep story request. The disclosure is
/// deliberately in-app (not hidden behind the Privacy Policy) and names both
/// the recipient and every category of gallery data sent for AI processing.
struct AIDataSharingConsentView: View {
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Before AI analysis")
                                .font(Theme.Typography.display)
                            Text("Roast My Gallery sends the analysis content below to our backend, which passes it to Google Gemini, a third-party AI service, to write your result.")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineSpacing(Theme.Typography.bodyLineSpacing)
                        }

                        disclosureCard(
                            title: "Sent to Google Gemini",
                            icon: "arrow.up.forward",
                            items: [
                                "Photo totals and counts, including selfies, screenshots, and favorites",
                                "Scene/category counts and monthly or time-of-day patterns",
                                "Coarse relative location clusters — never coordinates or place names",
                                "Your chosen voice and app language"
                            ]
                        )

                        disclosureCard(
                            title: "Not sent with this permission",
                            icon: "hand.raised",
                            items: [
                                "Your photos, photo identifiers, filenames, names, or precise locations",
                                "Photos are shared only if a separate screen shows the exact batch and you approve it"
                            ]
                        )

                        Text("This data is used only to generate your requested result, not for advertising or tracking. If you choose Not Now, nothing is sent and the analysis does not start. You can revoke permission later in Settings.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineSpacing(3)

                        Link("Read Privacy Policy", destination: AppConfig.privacyPolicyURL)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.accent)

                        Button("Allow AI Processing") {
                            AIDataSharingConsent.grant()
                            Haptics.primary()
                            onAllow()
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button("Not Now") {
                            onDecline()
                        }
                        .buttonStyle(QuietButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func disclosureCard(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label(title, systemImage: icon)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Text("•")
                    Text(item)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .themedCard()
    }
}

/// Trust feature: shows the user exactly what data left the device for their
/// most recent analysis. Statistics live in `GalleryStatsView`; this page is
/// purely about data transparency — a privacy explainer plus a plain-language
/// summary of the exact payload (no raw JSON, on purpose — see #plainSummary).
struct DataTransparencyView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    explainer

                    // Latest stats that were actually sent to the backend: a
                    // standalone hand-picked run's placeholder stats never
                    // leave the device, so showing them here as "the payload"
                    // would be wrong (see latestScanStats).
                    if let stats = history.latestScanStats {
                        Text("WHAT YOUR LAST ANALYSIS SENT")
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        plainSummary(stats)
                    } else {
                        emptyState
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .navigationTitle("Data Sent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            bullet(icon: "checkmark.circle",
                   text: "Only after you allow AI processing, the statistics below plus your chosen voice and app language are sent through our backend to Google Gemini.")
            bullet(icon: "xmark.circle",
                   text: "What this permission never sends: your photos, photo identifiers, precise locations, filenames, or names.")
            bullet(icon: "hand.raised",
                   text: "Deep Analysis shows you the exact photos it wants to caption before anything is sent. You can drop any of them, or send none at all.")
        }
        .themedCard()
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.Colors.accent)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(3)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.Colors.accent)
            Text("No analyses yet")
                .font(Theme.Typography.headline)
            Text("Once you run an analysis, a plain-language breakdown of exactly what it sent will appear here.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    // MARK: - Plain-language payload

    /// A human-readable rendering of the exact `PhotoStats` that was sent — the
    /// same data the raw JSON used to show, translated into rows anyone can
    /// read. Only fields with something to report are listed, so the summary
    /// stays honest without padding it with zeros.
    private func plainSummary(_ stats: PhotoStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(payloadRows(stats).enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().overlay(Theme.Colors.background)
                }
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    Text(row.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.m)
                    Text(row.value)
                        .font(Theme.Typography.headline)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, Theme.Spacing.s)
            }
        }
        .themedCard(fill: Theme.Colors.cream)
    }

    private struct PayloadRow { let label: String; let value: String }

    private func payloadRows(_ stats: PhotoStats) -> [PayloadRow] {
        var rows: [PayloadRow] = [
            PayloadRow(label: "Time range", value: stats.scope.displayLabel),
            PayloadRow(label: "Photos analyzed",
                       value: "\(stats.analyzedPhotos) of \(stats.totalPhotos)"),
        ]

        if stats.selfieCount > 0 {
            rows.append(PayloadRow(label: "Selfies", value: "\(stats.selfieCount)"))
        }
        if stats.screenshotCount > 0 {
            rows.append(PayloadRow(label: "Screenshots", value: "\(stats.screenshotCount)"))
        }
        if stats.favoriteCount > 0 {
            rows.append(PayloadRow(label: "Favorites", value: "\(stats.favoriteCount)"))
        }

        let topCategories = stats.topCategories.prefix(3)
            .map { "\($0.category) (\($0.count))" }
            .joined(separator: ", ")
        if !topCategories.isEmpty {
            rows.append(PayloadRow(label: "Top things we saw", value: topCategories))
        }

        let pets = stats.animalCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
        if !pets.isEmpty {
            rows.append(PayloadRow(label: "Animals spotted", value: pets))
        }

        if let peakHour = stats.photosByHourOfDay.enumerated()
            .max(by: { $0.element < $1.element })?.offset,
           stats.photosByHourOfDay.contains(where: { $0 > 0 }) {
            rows.append(PayloadRow(label: "Busiest hour",
                                   value: String(format: "%02d:00", peakHour)))
        }

        if !stats.topLocationClusters.isEmpty {
            let count = stats.topLocationClusters.count
            rows.append(PayloadRow(label: "Location",
                                   value: "\(count) rough \(count == 1 ? "area" : "areas") — no places named"))
        }

        return rows
    }
}
