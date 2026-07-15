import SwiftUI

/// Trust feature: shows the user exactly what statistics left the device for
/// their most recent analysis — i.e. the only data sent in the free tier.
///
/// Presentation is a clean, human-readable summary ("Selfie ratio: 23%") built
/// from `PhotoStats`. The exact JSON payload is still available, tucked behind a
/// disclosure, so the "actual bytes" trust guarantee is preserved without
/// leading with a raw dump.
struct DataTransparencyView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    explainer

                    if let stats = history.latest?.stats {
                        Text("Sent for your latest analysis")
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        summaryCard(stats)
                        rawPayloadDisclosure(stats)
                    } else {
                        emptyState
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .navigationTitle("Your Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            bullet(icon: "checkmark.circle",
                   text: "What leaves your device: the anonymous statistics below, plus your chosen voice. That's the entire request.")
            bullet(icon: "xmark.circle",
                   text: "What never leaves: your photos, photo identifiers, precise locations, names — anything identifying.")
            bullet(icon: "hand.raised",
                   text: "Deep Analysis (Pro) uploads only photos you hand-pick, and only after you approve that exact batch.")
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
            Text("Once you run an analysis, the exact statistics it sends will appear here, in plain language and as raw data.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    // MARK: - Readable summary

    private func summaryCard(_ stats: PhotoStats) -> some View {
        let rows = summaryRows(stats)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Theme.Colors.background)
                }
                HStack(alignment: .top) {
                    Text(row.label)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer(minLength: Theme.Spacing.m)
                    Text(row.value)
                        .font(Theme.Typography.headline)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private struct SummaryRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private func summaryRows(_ stats: PhotoStats) -> [SummaryRow] {
        var rows: [SummaryRow] = []

        rows.append(SummaryRow(label: "Scope", value: scopeLabel(stats.scope)))
        rows.append(SummaryRow(
            label: "Photos analyzed",
            value: "\(stats.analyzedPhotos) of \(stats.totalPhotos)"
        ))
        rows.append(SummaryRow(
            label: "Selfie ratio",
            value: "\(Int((stats.selfieRatio * 100).rounded()))%"
        ))
        rows.append(SummaryRow(label: "Selfies", value: "\(stats.selfieCount)"))
        rows.append(SummaryRow(label: "Screenshots", value: "\(stats.screenshotCount)"))
        rows.append(SummaryRow(label: "Favorites", value: "\(stats.favoriteCount)"))

        if let top = stats.topCategories.first {
            rows.append(SummaryRow(
                label: "Top category",
                value: "\(top.category.capitalized) (\(top.count) \(top.count == 1 ? "photo" : "photos"))"
            ))
        }
        if stats.topCategories.count > 1 {
            let others = stats.topCategories.dropFirst().prefix(3)
                .map { "\($0.category.capitalized) (\($0.count))" }
                .joined(separator: ", ")
            if !others.isEmpty {
                rows.append(SummaryRow(label: "Also common", value: others))
            }
        }

        if let busiest = busiestHourLabel(stats.photosByHourOfDay) {
            rows.append(SummaryRow(label: "Busiest hour", value: busiest))
        }

        if let topAnimal = stats.animalCounts.max(by: { $0.value < $1.value }) {
            rows.append(SummaryRow(
                label: "Top animal",
                value: "\(topAnimal.key.capitalized) (\(topAnimal.value))"
            ))
        }

        if !stats.topLocationClusters.isEmpty {
            let topShare = stats.topLocationClusters.map(\.share).max() ?? 0
            rows.append(SummaryRow(
                label: "Location clusters",
                value: "\(stats.topLocationClusters.count) (top holds \(Int((topShare * 100).rounded()))%)"
            ))
        }

        if !stats.faceCountBuckets.isEmpty {
            // Present in a stable, readable order rather than dictionary order.
            let order = ["0 faces", "1 face", "2+ faces"]
            let ordered = stats.faceCountBuckets
                .sorted { lhs, rhs in
                    (order.firstIndex(of: lhs.key) ?? .max) < (order.firstIndex(of: rhs.key) ?? .max)
                }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            rows.append(SummaryRow(label: "Faces", value: ordered))
        }

        rows.append(SummaryRow(
            label: "Generated",
            value: stats.generatedAt.formatted(date: .abbreviated, time: .shortened)
        ))

        return rows
    }

    private func scopeLabel(_ scope: AnalysisScope) -> String {
        switch scope {
        case .lastThreeMonths: return "Last 3 months"
        case .fullHistory: return "Full history"
        }
    }

    private func busiestHourLabel(_ hours: [Int]) -> String? {
        guard let maxCount = hours.max(), maxCount > 0,
              let hour = hours.firstIndex(of: maxCount) else { return nil }
        var components = DateComponents()
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return nil }
        let time = date.formatted(.dateTime.hour())
        return "\(time) (\(maxCount) photos)"
    }

    // MARK: - Raw payload (exact bytes)

    private func rawPayloadDisclosure(_ stats: PhotoStats) -> some View {
        DisclosureGroup {
            if let json = prettyJSON(stats) {
                ScrollView(.horizontal) {
                    Text(json)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.s)
                }
                .scrollIndicators(.hidden)
            }
        } label: {
            Text("Show the exact data (JSON)")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
        }
        .tint(Theme.Colors.accent)
        .themedCard(fill: Theme.Colors.cream)
    }

    private func prettyJSON(_ stats: PhotoStats) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stats) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
