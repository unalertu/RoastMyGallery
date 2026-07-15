import SwiftUI

@main
struct RoastMyGalleryApp: App {
    @State private var purchaseManager = PurchaseManager()
    @State private var historyStore: AnalysisHistoryStore
    @State private var scanViewModel: ScanViewModel

    init() {
        let environment = AppEnvironment.live()
        let history = AnalysisHistoryStore()
        _historyStore = State(initialValue: history)
        _scanViewModel = State(initialValue: ScanViewModel(environment: environment, history: history))
        #if DEBUG
        ShareCardDebugExporter.renderAllIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(purchaseManager)
                .environment(historyStore)
                .environment(scanViewModel)
                // Pastel palette is tuned for light backgrounds only; a proper
                // dark variant is a future design pass.
                .preferredColorScheme(.light)
                .task { await purchaseManager.loadProducts() }
        }
    }
}
