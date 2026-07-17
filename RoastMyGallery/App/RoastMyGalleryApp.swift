import SwiftUI
import UserNotifications

@main
struct RoastMyGalleryApp: App {
    @State private var purchaseManager: PurchaseManager
    @State private var historyStore: AnalysisHistoryStore
    @State private var scanViewModel: ScanViewModel
    @State private var deepVisionRunner: DeepVisionRunner

    init() {
        // Configure RevenueCat before anything touches `Purchases.shared`
        // (PurchaseManager's init subscribes to the CustomerInfo stream).
        PurchaseManager.configure()

        let environment = AppEnvironment.live()
        let history = AnalysisHistoryStore()
        let purchases = PurchaseManager()
        let scanVM = ScanViewModel(
            environment: environment,
            history: history,
            purchaseManager: purchases
        )
        let deepVision = DeepVisionRunner(
            service: environment.deepVision,
            history: history,
            purchaseManager: purchases
        )
        _purchaseManager = State(initialValue: purchases)
        _historyStore = State(initialValue: history)
        _scanViewModel = State(initialValue: scanVM)
        _deepVisionRunner = State(initialValue: deepVision)

        // Completion-notification taps must find their way back to the
        // finished analysis. The delegate has to be registered before launch
        // finishes so a tap that cold-starts the app is still delivered.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        NotificationRouter.shared.openAnalysis = { id, flow in
            switch flow {
            case .deepVision:
                if let id, let record = history.records.first(where: { $0.id == id }) {
                    deepVision.openResult(record)
                } else {
                    // Failure notifications carry no record — reopen the
                    // picking screen, which shows the error inline.
                    deepVision.reopenFailedRun()
                }
            case .scan:
                scanVM.openResult(withID: id)
            }
        }
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
                .environment(deepVisionRunner)
                // Pastel palette is tuned for light backgrounds only; a proper
                // dark variant is a future design pass.
                .preferredColorScheme(.light)
                .task { await purchaseManager.bootstrap() }
        }
    }
}
