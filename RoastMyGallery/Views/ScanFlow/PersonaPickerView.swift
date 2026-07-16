import SwiftUI

/// Ready-to-scan screen: choose what to analyze (full history, a month, or an
/// album), then a voice. Two equal, neutral persona cards — no default
/// selection, no premium badges on those; the scope chips are the only
/// gated part of this screen.
struct PersonaPickerView: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showPaywall = false
    @State private var paywallContext: PaywallView.Context = .general
    @State private var showMonthPicker = false
    @State private var showAlbumPicker = false
    @State private var showDateRangePicker = false
    @State private var albums: [PhotoLibraryService.AlbumInfo] = []

    private var isDeep: Bool { scanViewModel.selectedDepth == .deep }
    private var analysisCost: Int { PurchaseManager.cost(for: scanViewModel.selectedDepth) }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            if isDeep {
                deepScopeSection
            } else {
                scopeSection
            }

            VStack(spacing: Theme.Spacing.s) {
                Text("Pick a voice")
                    .font(Theme.Typography.display)
                Text("How should we talk about your photos?")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.m) {
                ForEach(Persona.allCases) { persona in
                    PersonaCard(
                        persona: persona,
                        isSelected: scanViewModel.selectedPersona == persona
                    ) {
                        scanViewModel.selectedPersona = persona
                    }
                }
            }
            .padding(.top, Theme.Spacing.m)

            if isDeep { deepConsentCard }

            Spacer()

            Button(isDeep ? "Start Deep Analysis" : "Analyze My Photos") {
                // Client-side affordability check is UX only — route to the
                // paywall early if the balance looks short. The authoritative
                // gate is RevenueCat rejecting an over-spend server-side.
                if purchaseManager.canAfford(analysisCost) {
                    scanViewModel.startScan(appUserID: purchaseManager.appUserID)
                } else {
                    paywallContext = .analysis(have: purchaseManager.creditBalance)
                    showPaywall = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canStart)

            Text(startFootnote)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.l)
        .animation(Theme.motion, value: scanViewModel.selectedPersona)
        .animation(Theme.motion, value: scanViewModel.selectedScope)
        .animation(Theme.motion, value: scanViewModel.hasDeepConsent)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: paywallContext)
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet { scope in
                scanViewModel.selectedScope = scope
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerSheet(albums: albums) { scope in
                scanViewModel.selectedScope = scope
            }
        }
        .sheet(isPresented: $showDateRangePicker) {
            DateRangePickerSheet { scope in
                scanViewModel.selectedScope = scope
            }
        }
    }

    /// Deep requires a chosen date range AND consent; standard just needs a
    /// voice (its scope defaults to full history).
    private var canStart: Bool {
        guard scanViewModel.selectedPersona != nil else { return false }
        if isDeep {
            return isDateRangeSelected && scanViewModel.hasDeepConsent
        }
        return true
    }

    private var startFootnote: String {
        if scanViewModel.selectedPersona == nil { return "Choose a voice to begin" }
        if isDeep && !isDateRangeSelected { return "Pick a date range to analyze" }
        if isDeep && !scanViewModel.hasDeepConsent { return "Agree to photo captioning to continue" }
        let unit = analysisCost == 1 ? "credit" : "credits"
        return "\(analysisCost) \(unit) • you have \(purchaseManager.creditBalance)"
    }

    // MARK: - Scope

    private var scopeSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                ScopeChip(
                    title: "All Time",
                    systemImage: "clock",
                    isSelected: scanViewModel.selectedScope == .fullHistory,
                    isLocked: false
                ) {
                    scanViewModel.selectedScope = .fullHistory
                }
                ScopeChip(
                    title: "Choose Month",
                    systemImage: "calendar",
                    isSelected: isDateRangeSelected,
                    isLocked: !purchaseManager.hasUnlockedModes
                ) {
                    tappedMonthChip()
                }
                ScopeChip(
                    title: "Choose Album",
                    systemImage: "square.stack",
                    isSelected: isAlbumSelected,
                    isLocked: !purchaseManager.hasUnlockedModes
                ) {
                    tappedAlbumChip()
                }
            }

            Text("Analyzing: \(scanViewModel.selectedScope.displayLabel)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Deep scope + consent

    /// Deep analysis replaces the three scope chips with a single required
    /// date-range picker (capped at 1 year in the sheet itself).
    private var deepScopeSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Deep Analysis")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.accent)

            Button {
                showDateRangePicker = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .light))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isDateRangeSelected ? "Date range" : "Choose a date range")
                            .font(Theme.Typography.headline)
                        Text(isDateRangeSelected
                             ? scanViewModel.selectedScope.displayLabel
                             : "Up to one year of photos")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .foregroundStyle(isDateRangeSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.m)
                .background(
                    isDateRangeSelected ? Theme.Colors.accentSoft : Theme.Colors.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.button)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button)
                        .stroke(isDateRangeSelected ? Theme.Colors.accent : .clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Deep uploads the photos shown in the results for AI captions, so it
    /// requires explicit, unchecked-by-default consent every run — matching
    /// the app's contract that image uploads are always opt-in.
    private var deepConsentCard: some View {
        Toggle(isOn: Binding(
            get: { scanViewModel.hasDeepConsent },
            set: { scanViewModel.hasDeepConsent = $0 }
        )) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Caption my photos with AI")
                    .font(Theme.Typography.headline)
                Text("The handful of photos shown in your results — and only those — will be resized on your device and uploaded once for a short caption each. Your other photos never leave your phone; the story itself is built from anonymous stats.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineSpacing(2)
            }
        }
        .tint(Theme.Colors.accent)
        .themedCard()
    }

    private var isDateRangeSelected: Bool {
        if case .dateRange = scanViewModel.selectedScope { return true }
        return false
    }

    private var isAlbumSelected: Bool {
        if case .album = scanViewModel.selectedScope { return true }
        return false
    }

    private func tappedMonthChip() {
        guard purchaseManager.hasUnlockedModes else {
            paywallContext = .lockedMode(name: "Date & month picking")
            showPaywall = true
            return
        }
        showMonthPicker = true
    }

    private func tappedAlbumChip() {
        guard purchaseManager.hasUnlockedModes else {
            paywallContext = .lockedMode(name: "Album analysis")
            showPaywall = true
            return
        }
        albums = scanViewModel.fetchAlbums()
        showAlbumPicker = true
    }
}

private struct PersonaCard: View {
    let persona: Persona
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: Theme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.persona(persona))
                        .frame(width: 56, height: 56)
                    Image(systemName: persona.symbolName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.top, Theme.Spacing.s)

                Text(persona.displayName)
                    .font(Theme.Typography.headline)
                Text(persona.tagline)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(persona.pickerDescription)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(isSelected ? Theme.Colors.accent : .clear, lineWidth: 2)
            )
            .softShadow()
        }
        .buttonStyle(.plain)
    }
}

/// One scope option in the "what to analyze" row. Locked chips still show
/// their real label (never hidden) — tapping routes to the paywall instead
/// of the picker.
private struct ScopeChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .light))
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .offset(x: 10, y: -6)
                    }
                }
                Text(title)
                    .font(Theme.Typography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)
            .background(
                isSelected ? Theme.Colors.accentSoft : Theme.Colors.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button)
                    .stroke(isSelected ? Theme.Colors.accent : .clear, lineWidth: 1.5)
            )
            .opacity(isLocked ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// Month/year wheel picker. Deliberately month-granularity only (not a full
/// calendar date picker) — "which month" is the useful unit here, and it
/// keeps the sheet to one screen with no extra taps.
private struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (AnalysisScope) -> Void

    private static let calendar = Calendar.current
    private static let monthSymbols = DateFormatter().standaloneMonthSymbols ?? []
    private static let years: [Int] = {
        let current = calendar.component(.year, from: .now)
        return Array((current - 8)...current)
    }()

    @State private var selectedMonthIndex: Int
    @State private var selectedYear: Int

    init(onSelect: @escaping (AnalysisScope) -> Void) {
        self.onSelect = onSelect
        let now = Date()
        _selectedMonthIndex = State(initialValue: Self.calendar.component(.month, from: now) - 1)
        _selectedYear = State(initialValue: Self.calendar.component(.year, from: now))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                Text("Pick a month")
                    .font(Theme.Typography.title)
                    .padding(.top, Theme.Spacing.l)

                HStack(spacing: 0) {
                    Picker("Month", selection: $selectedMonthIndex) {
                        ForEach(Array(Self.monthSymbols.enumerated()), id: \.offset) { index, name in
                            Text(name.capitalized).tag(index)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Year", selection: $selectedYear) {
                        ForEach(Self.years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Spacer()

                Button("Use \(monthLabel)") {
                    onSelect(scope)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
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
    }

    private var monthLabel: String {
        guard Self.monthSymbols.indices.contains(selectedMonthIndex) else { return "" }
        return "\(Self.monthSymbols[selectedMonthIndex].capitalized) \(selectedYear)"
    }

    private var scope: AnalysisScope {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonthIndex + 1
        components.day = 1
        let calendar = Self.calendar
        let start = calendar.date(from: components) ?? .now
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return .dateRange(start: start, end: end, label: monthLabel)
    }
}

/// Lists the user's non-empty regular albums; tapping one sets that album as
/// the scan scope.
private struct AlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let albums: [PhotoLibraryService.AlbumInfo]
    let onSelect: (AnalysisScope) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if albums.isEmpty {
                    EmptyStateView(
                        systemImage: "photo.stack",
                        title: "No albums found",
                        message: "Create an album in the Photos app, then come back here."
                    )
                    .padding(Theme.Spacing.l)
                } else {
                    List(albums) { album in
                        Button {
                            onSelect(.album(identifier: album.id, name: album.title))
                            dismiss()
                        } label: {
                            HStack {
                                Text(album.title)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text("\(album.photoCount)")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Choose an album")
            .navigationBarTitleDisplayMode(.inline)
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
    }
}
