import SwiftUI

/// Tab 2 — past analyses. Free tier can open only the most recent record;
/// older rows show a lock and route to the paywall (records are kept on disk,
/// so upgrading unlocks them retroactively).
struct HistoryView: View {
    @Environment(AnalysisHistoryStore.self) private var history
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showPaywall = false

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
                InsightView(record: record)
            }
        }
        .tint(Theme.Colors.accent)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var recordList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(Array(history.records.enumerated()), id: \.element.id) { index, record in
                    // Free tier: only the newest record is viewable.
                    let locked = !purchaseManager.entitlements.isPro && index > 0

                    if locked {
                        Button { showPaywall = true } label: {
                            HistoryRow(record: record, locked: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: record) {
                            HistoryRow(record: record, locked: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HistoryRow: View {
    let record: AnalysisRecord
    let locked: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                Circle()
                    .fill(locked ? Theme.Colors.cream : Theme.Colors.persona(record.persona))
                    .frame(width: 44, height: 44)
                Image(systemName: locked ? "lock" : record.persona.symbolName)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(locked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(locked ? "Unlock with Pro" : record.insight.headline)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(locked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.s) {
                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(record.persona.displayName)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
        }
        .themedCard()
    }
}
