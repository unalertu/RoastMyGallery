import SwiftUI

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
                   text: "What leaves your device: the anonymous counts below, plus your chosen voice and app language. That's the whole request.")
            bullet(icon: "xmark.circle",
                   text: "What never leaves: your photos, photo identifiers, precise locations, names — anything identifying.")
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
