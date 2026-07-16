import SwiftUI

/// Deep-analysis date range picker: From / To month-year wheels, capped at
/// 12 months. Month granularity on purpose, matching `MonthPickerSheet` —
/// "which months" is the useful unit, and it keeps the sheet to one screen.
///
/// Limit UX: the wheels themselves are never blocked (fighting a wheel feels
/// broken); instead the live summary line flips into a warning state, the
/// confirm button disables, and a one-tap "Trim to 12 months" fix pulls the
/// start month up. Exactly 12 months is valid.
struct DateRangePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AnalysisScope) -> Void

    private static let calendar = Calendar.current
    private static let monthSymbols = DateFormatter().standaloneMonthSymbols ?? []
    private static let years: [Int] = {
        let current = calendar.component(.year, from: .now)
        return Array((current - 8)...current)
    }()
    private static let maxMonths = 12

    @State private var fromMonthIndex: Int
    @State private var fromYear: Int
    @State private var toMonthIndex: Int
    @State private var toYear: Int

    init(onSelect: @escaping (AnalysisScope) -> Void) {
        self.onSelect = onSelect
        // Default to the last 12 months — the full range deep analysis covers.
        let now = Date()
        let to = (month: Self.calendar.component(.month, from: now) - 1,
                  year: Self.calendar.component(.year, from: now))
        let fromDate = Self.calendar.date(byAdding: .month, value: -(Self.maxMonths - 1), to: now) ?? now
        _fromMonthIndex = State(initialValue: Self.calendar.component(.month, from: fromDate) - 1)
        _fromYear = State(initialValue: max(Self.calendar.component(.year, from: fromDate), Self.years.first ?? to.year))
        _toMonthIndex = State(initialValue: to.month)
        _toYear = State(initialValue: to.year)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                VStack(spacing: Theme.Spacing.s) {
                    Text("Pick a date range")
                        .font(Theme.Typography.title)
                    Text("Deep analysis covers up to one year of photos.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, Theme.Spacing.l)

                wheelRow(label: "From", monthIndex: $fromMonthIndex, year: $fromYear)
                wheelRow(label: "To", monthIndex: $toMonthIndex, year: $toYear)

                summaryLine

                Spacer()

                if monthCount > Self.maxMonths {
                    Button("Trim to 12 months") { trimToLimit() }
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.accent)
                }

                Button(confirmTitle) {
                    onSelect(scope)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
            }
            .padding(Theme.Spacing.l)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
        .animation(Theme.motion, value: isValid)
        .animation(Theme.motion, value: monthCount)
    }

    // MARK: - Pieces

    private func wheelRow(label: String, monthIndex: Binding<Int>, year: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: 0) {
                Picker("\(label) month", selection: monthIndex) {
                    ForEach(Array(Self.monthSymbols.enumerated()), id: \.offset) { index, name in
                        Text(name.capitalized).tag(index)
                    }
                }
                .pickerStyle(.wheel)

                Picker("\(label) year", selection: year) {
                    ForEach(Self.years, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 96)
        }
    }

    /// Live range summary; flips into a warning when the range is invalid.
    @ViewBuilder
    private var summaryLine: some View {
        if isValid {
            Text("\(rangeLabel) · \(monthCount == 1 ? "1 month" : "\(monthCount) months")")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else {
            Label(
                monthCount < 1
                    ? "End month is before start month"
                    : "Maximum range is 12 months",
                systemImage: "exclamationmark.triangle"
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.danger)
        }
    }

    // MARK: - Range math

    /// Whole months in the range, inclusive on both ends (Jul–Jul = 1).
    /// Zero or negative when "To" precedes "From".
    private var monthCount: Int {
        (toYear * 12 + toMonthIndex) - (fromYear * 12 + fromMonthIndex) + 1
    }

    private var isValid: Bool { (1...Self.maxMonths).contains(monthCount) }

    /// Pulls "From" up to exactly 12 months before "To".
    private func trimToLimit() {
        let target = (toYear * 12 + toMonthIndex) - (Self.maxMonths - 1)
        fromYear = target / 12
        fromMonthIndex = target % 12
    }

    private var confirmTitle: String {
        isValid ? "Deep Analyze \(rangeLabel)" : "Pick up to 12 months"
    }

    private func monthLabel(monthIndex: Int, year: Int) -> String {
        guard Self.monthSymbols.indices.contains(monthIndex) else { return "" }
        return "\(Self.monthSymbols[monthIndex].capitalized) \(year)"
    }

    private var rangeLabel: String {
        let from = monthLabel(monthIndex: fromMonthIndex, year: fromYear)
        let to = monthLabel(monthIndex: toMonthIndex, year: toYear)
        return from == to ? from : "\(from) – \(to)"
    }

    /// Same boundary construction as `MonthPickerSheet`: first instant of the
    /// "From" month through the last second of the "To" month, inclusive.
    private var scope: AnalysisScope {
        var components = DateComponents()
        components.year = fromYear
        components.month = fromMonthIndex + 1
        components.day = 1
        let calendar = Self.calendar
        let start = calendar.date(from: components) ?? .now

        var endComponents = DateComponents()
        endComponents.year = toYear
        endComponents.month = toMonthIndex + 1
        endComponents.day = 1
        let toStart = calendar.date(from: endComponents) ?? start
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: toStart) ?? toStart

        return .dateRange(start: start, end: end, label: rangeLabel)
    }
}
