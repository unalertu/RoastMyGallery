import SwiftUI

/// Trust feature: shows the user exactly what raw data left the device for
/// their most recent analysis. Statistics are now in `GalleryStatsView`;
/// this page is purely about data transparency — privacy explainer + raw JSON.
struct DataTransparencyView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    explainer

                    if let stats = history.latest?.stats {
                        Text("LATEST DATA PAYLOAD")
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.textSecondary)

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
        .navigationTitle("Data Sent")
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
            Text("Once you run an analysis, the exact data it sends will appear here as raw JSON.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
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
