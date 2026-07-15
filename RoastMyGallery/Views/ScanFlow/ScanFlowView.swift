import SwiftUI

/// The modal analysis flow, presented full-screen from Home:
/// permission (if needed) → persona pick → scan progress → results.
///
/// The Close button is always available — including mid-scan, where it
/// cancels the in-flight work — so the user can back out at any point.
/// Results are already persisted by the time `.results` shows, so closing
/// from there simply lands on Home with the new analysis visible.
struct ScanFlowView: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    switch scanViewModel.phase {
                    case .needsPermission, .permissionDenied:
                        PermissionView()
                    case .readyToScan:
                        PersonaPickerView()
                    case .scanning, .generatingInsight:
                        ScanProgressView()
                    case .results(let record):
                        InsightView(record: record)
                    case .failed(let message):
                        failureScreen(message)
                    }
                }
                .transition(.opacity)
            }
            .animation(Theme.motion, value: scanViewModel.phase)
            .foregroundStyle(Theme.Colors.textPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        scanViewModel.cancelScan()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                if case .results = scanViewModel.phase {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .font(Theme.Typography.headline)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .onChange(of: scenePhase) { _, newPhase in
            // Catch permission changes made in Settings while backgrounded.
            if newPhase == .active { scanViewModel.refreshPermissionPhase() }
        }
        .onChange(of: scanViewModel.phase) { _, newPhase in
            // A completed analysis is charged 1 credit by the backend; pull the
            // authoritative balance so Home/Settings reflect the spend.
            if case .results = newPhase {
                Task { await purchaseManager.reconcileAfterSpend() }
            }
        }
    }

    private func failureScreen(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "cloud.drizzle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("That didn't work")
                .font(Theme.Typography.title)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Try Again") { scanViewModel.reset() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.l)
    }
}
