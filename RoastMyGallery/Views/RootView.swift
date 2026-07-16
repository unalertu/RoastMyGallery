import SwiftUI

/// App shell: a persistent three-tab structure. The scan flow is a modal
/// (`ScanFlowView`) presented HERE — not from Home — off the shared
/// `ScanViewModel.isFlowPresented`, so a minimized run can be reopened from
/// any tab (via the status banner) or from a completion notification, and the
/// run itself never depends on which screen launched it.
struct RootView: View {
    @Environment(ScanViewModel.self) private var scanViewModel

    /// Standard iPhone tab-bar height (this app is iPhone-only, portrait-only)
    /// plus a breath of space, so the banner floats just above the bar.
    private static let tabBarClearance: CGFloat = 49 + Theme.Spacing.s

    var body: some View {
        @Bindable var scanViewModel = scanViewModel

        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
    }
}

#Preview {
    let history = AnalysisHistoryStore()
    let purchases = PurchaseManager()
    RootView()
        .environment(ScanViewModel(environment: .live(), history: history, purchaseManager: purchases))
        .environment(purchases)
        .environment(history)
}
