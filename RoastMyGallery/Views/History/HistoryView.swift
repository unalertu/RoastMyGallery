import SwiftUI

/// Tab 2 — past analyses. Every saved record is viewable: in the credit model
/// you already paid a credit to generate each one, so there's nothing to gate.
struct HistoryView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if history.records.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "No history yet",
                        message: "Every analysis you run will be saved here, so you can watch your habits change over time."
                    )
                } else {
                    recordList
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .navigationDestination(for: AnalysisRecord.self) { record in
                if record.deepVision != nil {
                    DeepVisionRecordView(record: record)
                } else {
                    InsightView(record: record)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var recordList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(history.records, id: \.id) { record in
                    NavigationLink(value: record) {
                        HistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HistoryRow: View {
    let record: AnalysisRecord

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.persona(record.persona))
                    .frame(width: 44, height: 44)
                Image(systemName: record.persona.symbolName)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(record.insight.headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.s) {
                    // The library slice this story covers (e.g. "April 2024"),
                    // so months are distinguishable at a glance — not the
                    // created date, which follows it.
                    Text(record.stats.scope.displayLabel)
                        .foregroundStyle(Theme.Colors.textPrimary.opacity(0.8))
                    Text("·")
                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(record.persona.displayName)
                    if record.deepVision != nil {
                        Text("·")
                        Label("Deep Vision", systemImage: "sparkles")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .lineLimit(1)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
        }
        .themedCard()
    }
}
