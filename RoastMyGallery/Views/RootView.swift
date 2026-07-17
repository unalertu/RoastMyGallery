import SwiftUI

/// App shell: a persistent three-tab structure. Both analysis flows are
/// modals presented HERE — not from Home — off their models' shared
/// `isFlowPresented` (`ScanViewModel` for the scan flow, `DeepVisionRunner`
/// for hand-picked Deep Vision), so a minimized run can be reopened from any
/// tab (via the status banner) or from a completion notification, and the
/// runs themselves never depend on which screen launched them.
/// The three root tabs. Home holds a binding to the selection so its
/// "See all" shortcut can jump to History.
enum AppTab: Hashable {
    case home, history, settings
}

struct RootView: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(DeepVisionRunner.self) private var deepVisionRunner

    @State private var selectedTab: AppTab = .home

    /// Standard iPhone tab-bar height (this app is iPhone-only, portrait-only)
    /// plus a breath of space, so the banner floats just above the bar.
    private static let tabBarClearance: CGFloat = 49 + Theme.Spacing.s

    var body: some View {
        @Bindable var scanViewModel = scanViewModel
        @Bindable var deepVisionRunner = deepVisionRunner

        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Theme.Colors.accent)
        .overlay(alignment: .bottom) {
            AnalysisStatusBanner()
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Self.tabBarClearance)
        }
        .fullScreenCover(isPresented: $scanViewModel.isFlowPresented) {
            ScanFlowView()
        }
        .fullScreenCover(isPresented: $deepVisionRunner.isFlowPresented) {
            DeepVisionFlowView()
        }
    }
}

#Preview {
    let environment = AppEnvironment.live()
    let history = AnalysisHistoryStore()
    let purchases = PurchaseManager()
    RootView()
        .environment(ScanViewModel(environment: environment, history: history, purchaseManager: purchases))
        .environment(DeepVisionRunner(service: environment.deepVision, history: history, purchaseManager: purchases))
        .environment(purchases)
        .environment(history)
}
