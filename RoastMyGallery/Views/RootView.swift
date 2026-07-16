import SwiftUI

/// App shell: a persistent three-tab structure. The scan flow itself is a
/// modal (`ScanFlowView`) launched from Home, not a screen the app lives in.
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.Colors.accent)
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
