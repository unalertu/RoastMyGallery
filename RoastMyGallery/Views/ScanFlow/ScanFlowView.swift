import SwiftUI
import StoreKit

/// The modal analysis flow, presented full-screen from `RootView` (off the
/// shared `ScanViewModel.isFlowPresented`): permission (if needed) → persona
/// pick → scan progress → results.
///
/// A leading button is always available, but its meaning depends on the run:
/// while the pipeline is working it MINIMIZES (the run continues behind
/// `AnalysisStatusBanner`; cancelling lives on the progress screen), and
/// otherwise it closes the flow. Results are already persisted by the time
/// `.results` shows, so closing from there lands on Home with the new
/// analysis visible.
struct ScanFlowView: View {
    @Environment(ScanViewModel.self) private var scanViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

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
                    case .scanning, .generatingInsight, .captioning:
                        ScanProgressView()
                    case .reviewingCaptionPhotos(let assetIDs):
                        CaptionReviewView(assetIDs: assetIDs)
                    case .results(let record):
                        InsightView(record: record, isInScanFlow: true)
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
                    if scanViewModel.isRunActive {
                        // Mid-run: minimize, never cancel — the run keeps
                        // working and the status banner takes over. Explicit
                        // cancellation stays on the progress screen.
                        Button {
                            Haptics.tap()
                            scanViewModel.minimizeFlow()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .accessibilityLabel("Minimize — analysis continues in the background")
                    } else {
                        Button {
                            scanViewModel.cancelScan()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
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
            switch newPhase {
            case .results:
                Haptics.success()
                // Automatic App Store rating ask, at the one genuine delight
                // moment: fresh results on screen. ReviewPrompter gates it (≥2
                // completed runs, once per version); the short delay lets the
                // results screen settle before the system sheet appears.
                if ReviewPrompter.shouldPromptNow() {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        requestReview()
                    }
                }
            case .failed:
                Haptics.error()
            default:
                break
            }
        }
        // Note: the gem spend is reflected by `ScanViewModel` the moment a
        // charged insight succeeds (see `reflectSpend`), so Home/Settings
        // update immediately. A cache re-open reaches `.results` without a
        // charge, which is exactly why reconciling here (on every `.results`)
        // was the wrong place — the view model knows which runs actually paid.
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
            Button("Try Again") {
                Haptics.tap()
                scanViewModel.reset()
            }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.l)
    }
}
