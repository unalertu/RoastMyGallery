import SwiftUI

/// Tab 2 — past analyses. Every saved record is viewable: in the gem model
/// you already paid a gem to generate each one, so there's nothing to gate.
struct HistoryView: View {
    @Environment(AnalysisHistoryStore.self) private var history

    // Last-used sort/filter, kept across launches (same @AppStorage pattern
    // as SettingsView). Stored as raw strings; `historyFilterAll` means the
    // dimension is unfiltered.
    @AppStorage("historySortOrder") private var sortOrderRaw = HistorySortOrder.newestFirst.rawValue
    @AppStorage("historyKindFilter") private var kindFilterRaw = historyFilterAll
    @AppStorage("historyPersonaFilter") private var personaFilterRaw = historyFilterAll

    @State private var showFilterSheet = false

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
                } else if visibleRecords.isEmpty {
                    noMatchesState
                } else {
                    recordList
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .toolbar {
                if !history.records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFilterSheet = true
                        } label: {
                            Image(systemName: isFilterActive
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .accessibilityLabel("Sort and filter")
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                HistoryFilterSheet(
                    sortOrderRaw: $sortOrderRaw,
                    kindFilterRaw: $kindFilterRaw,
                    personaFilterRaw: $personaFilterRaw
                )
                .presentationDetents([.medium])
            }
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

    // MARK: - Sort & filter state

    private var sortOrder: HistorySortOrder {
        HistorySortOrder(rawValue: sortOrderRaw) ?? .newestFirst
    }

    /// nil = "All" (the stored raw string isn't a case of the enum).
    private var kindFilter: AnalysisKind? { AnalysisKind(rawValue: kindFilterRaw) }
    private var personaFilter: Persona? { Persona(rawValue: personaFilterRaw) }

    /// Sort order alone doesn't fill the funnel icon — it changes ordering,
    /// not which records are shown.
    private var isFilterActive: Bool { kindFilter != nil || personaFilter != nil }

    private var visibleRecords: [AnalysisRecord] {
        var result = history.records
        if let kind = kindFilter { result = result.filter { $0.kind == kind } }
        if let persona = personaFilter { result = result.filter { $0.persona == persona } }
        // The store keeps records newest-first, so oldest-first is a reverse.
        if sortOrder == .oldestFirst { result.reverse() }
        return result
    }

    // MARK: - Pieces

    private var recordList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(visibleRecords, id: \.id) { record in
                    NavigationLink(value: record) {
                        HistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
            .animation(Theme.motion, value: visibleRecords)
        }
        .scrollIndicators(.hidden)
    }

    /// There is history, but none of it survives the active filters.
    private var noMatchesState: some View {
        VStack(spacing: Theme.Spacing.m) {
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "No matches",
                message: "Nothing in your history fits these filters."
            )
            Button("Clear filters") {
                kindFilterRaw = historyFilterAll
                personaFilterRaw = historyFilterAll
            }
            .buttonStyle(SoftButtonStyle())
            .padding(.horizontal, Theme.Spacing.xxl)
        }
    }
}

/// Stored value for an unfiltered dimension ("All").
private let historyFilterAll = "all"

/// Sort orders for the History list.
private enum HistorySortOrder: String, CaseIterable, Identifiable {
    case newestFirst, oldestFirst

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        }
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
                }
                .lineLimit(1)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

                AnalysisKindBadge(kind: record.kind)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
        }
        .themedCard()
    }
}

/// Small tinted chip naming which analysis tier produced a record.
private struct AnalysisKindBadge: View {
    let kind: AnalysisKind

    var body: some View {
        Label(kind.displayName, systemImage: kind.symbolName)
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Colors.kindText(kind))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.kindBackground(kind), in: Capsule())
    }
}

/// Sort + filter chooser for History. Writes straight through the bindings
/// (which back onto @AppStorage), so the list updates live behind the sheet
/// and the choice survives relaunches.
private struct HistoryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var sortOrderRaw: String
    @Binding var kindFilterRaw: String
    @Binding var personaFilterRaw: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        Text("Sort & filter")
                            .font(Theme.Typography.title)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, Theme.Spacing.l)

                        optionGroup("Sort") {
                            ForEach(HistorySortOrder.allCases) { order in
                                chip(order.displayName, isSelected: sortOrderRaw == order.rawValue) {
                                    sortOrderRaw = order.rawValue
                                }
                            }
                        }

                        optionGroup("Analysis type") {
                            chip("All", isSelected: kindFilterRaw == historyFilterAll) {
                                kindFilterRaw = historyFilterAll
                            }
                            ForEach(AnalysisKind.allCases) { kind in
                                chip(
                                    kind.displayName,
                                    systemImage: kind.symbolName,
                                    isSelected: kindFilterRaw == kind.rawValue
                                ) {
                                    kindFilterRaw = kind.rawValue
                                }
                            }
                        }

                        optionGroup("Persona") {
                            chip("All", isSelected: personaFilterRaw == historyFilterAll) {
                                personaFilterRaw = historyFilterAll
                            }
                            ForEach(Persona.allCases) { persona in
                                chip(
                                    persona.displayName,
                                    systemImage: persona.symbolName,
                                    isSelected: personaFilterRaw == persona.rawValue
                                ) {
                                    personaFilterRaw = persona.rawValue
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        sortOrderRaw = HistorySortOrder.newestFirst.rawValue
                        kindFilterRaw = historyFilterAll
                        personaFilterRaw = historyFilterAll
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    /// Uppercase group label over a horizontally scrolling chip row — the
    /// scroll keeps long rows ("Hand-Picked") intact on small screens.
    private func optionGroup(
        _ title: String,
        @ViewBuilder chips: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)

            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.s, content: chips)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isSelected ? Theme.Colors.background : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(
                isSelected ? Theme.Colors.accent : Theme.Colors.surface,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.motion, value: isSelected)
    }
}
