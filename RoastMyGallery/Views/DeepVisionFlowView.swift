import SwiftUI
import PhotosUI

/// The hand-picked Deep Vision flow, presented full-screen from `RootView`
/// (off the shared `DeepVisionRunner.isFlowPresented`) and driven entirely by
/// the runner, so it can be minimized mid-run and reopened from the status
/// banner or a completion notification — replacing the old view-owned pair
/// (HandPickedAnalysisView + DeepAnalysisConsentView).
///
/// Stages: persona pick (standalone entry only) → photo pick + explicit
/// per-batch consent → preparing/analyzing progress → results. Calm, no dark
/// patterns: consent is an unchecked opt-in every time, and the primary
/// button stays disabled until it's given.
///
/// This flow (with deep-run photo captions) is one of only two places in the
/// app that can trigger an image upload; every picked photo is downscaled
/// first (`ImageDownscaler`) — originals never leave the device.
struct DeepVisionFlowView: View {
    @Environment(DeepVisionRunner.self) private var runner
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(\.dismiss) private var dismiss

    /// Explicit, per-batch consent. Deliberately view-local @State: if the
    /// flow is closed and reopened, consent starts unchecked again.
    @State private var hasConsented = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    switch runner.phase {
                    case .idle:
                        if runner.persona == nil {
                            personaPicker
                        } else {
                            pickerAndConsent
                        }
                    case .preparing(let done, let total):
                        preparingProgress(done: done, total: total)
                    case .analyzing:
                        analyzingProgress
                    case .finished(let record):
                        resultsList(record)
                    }
                }
                .transition(.opacity)
            }
            .animation(Theme.motion, value: runner.phase)
            .navigationTitle("Deep Vision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if runner.isRunActive {
                        // Mid-run: minimize, never cancel — the batch keeps
                        // working behind the status banner. Cancel lives on
                        // the progress screens themselves.
                        Button {
                            runner.minimizeFlow()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .accessibilityLabel("Minimize — analysis continues in the background")
                    } else {
                        Button("Close") { dismiss() }
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .deepVision(have: purchaseManager.gemBalance))
        }
        // The backend's authoritative insufficient-gems rejection also
        // routes to the paywall, same as the pre-flight UX gate.
        .onChange(of: runner.errorMessage) { _, _ in
            if runner.failureWasInsufficientGems { showPaywall = true }
        }
    }

    // MARK: - Stage 0 (standalone entry only): pick a voice

    private var personaPicker: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            VStack(spacing: Theme.Spacing.s) {
                Text("Pick a voice")
                    .font(Theme.Typography.display)
                Text("How should we talk about the photos you choose?")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.m) {
                ForEach(Persona.allCases) { option in
                    Button {
                        withAnimation(Theme.motion) { runner.persona = option }
                    } label: {
                        VStack(spacing: Theme.Spacing.s) {
                            ZStack {
                                Circle()
                                    .fill(Theme.Colors.persona(option))
                                    .frame(width: 56, height: 56)
                                Image(systemName: option.symbolName)
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            Text(option.displayName)
                                .font(Theme.Typography.headline)
                            Text(option.tagline)
                                .font(Theme.Typography.label)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
                        .padding(Theme.Spacing.m)
                        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .softShadow()
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("Next: pick up to \(runner.maxBatchSize) photos · \(PurchaseManager.deepVisionCost) gems")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.l)
    }

    // MARK: - Stage 1: pick + consent

    private var pickerAndConsent: some View {
        @Bindable var runner = runner
        return VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.s) {
                Text("A closer look")
                    .font(Theme.Typography.title)
                Text("Pick up to \(runner.maxBatchSize) photos for individual, photo-by-photo commentary.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Theme.Typography.bodyLineSpacing)
            }
            .padding(.top, Theme.Spacing.l)

            PhotosPicker(
                selection: $runner.selection,
                maxSelectionCount: runner.maxBatchSize,
                matching: .images
            ) {
                Label(
                    runner.selection.isEmpty
                        ? "Choose Photos"
                        : "\(runner.selection.count) of \(runner.maxBatchSize) selected",
                    systemImage: "photo.badge.plus"
                )
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            }

            // Explicit, per-batch consent — required before any upload.
            Toggle(isOn: $hasConsented) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Send these photos for analysis")
                        .font(Theme.Typography.headline)
                    Text("The \(runner.selection.count) photos you picked — and only those — will be resized on your device, uploaded once, and read by an AI service. Nothing else ever leaves your device, and nothing is stored on the server.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(2)
                }
            }
            .tint(Theme.Colors.accent)
            .themedCard()
            .disabled(runner.selection.isEmpty)

            Spacer()

            if let errorMessage = runner.errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }

            Button {
                submit()
            } label: {
                Text("Analyze These Photos · \(PurchaseManager.deepVisionCost) gems")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(runner.selection.isEmpty || !hasConsented)
        }
        .padding(Theme.Spacing.l)
    }

    private func submit() {
        // UX-only affordability re-check (the balance may have changed since
        // the flow opened); the backend/RevenueCat is the real authority.
        guard purchaseManager.canAfford(PurchaseManager.deepVisionCost) else {
            showPaywall = true
            return
        }
        runner.submit(appUserID: purchaseManager.appUserID)
    }

    // MARK: - Stage 2: on-device preparation (downscale/compress)

    private func preparingProgress(done: Int, total: Int) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            ProgressRing(fraction: total > 0 ? Double(done) / Double(total) : 0)

            VStack(spacing: Theme.Spacing.s) {
                Text("Preparing your photos")
                    .font(Theme.Typography.title)
                Text("\(done) of \(total)")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.motion, value: done)
            }

            Text("Resizing on your device — originals never leave your phone.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            backgroundOrCancelButtons
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Stage 3: upload + vision model

    private var analyzingProgress: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            DriftingRing()

            VStack(spacing: Theme.Spacing.s) {
                Text("Reading your photos")
                    .font(Theme.Typography.title)
                if let persona = runner.persona {
                    Text("In your \(persona.displayName.lowercased()) voice…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            // Multiple images + a vision model: noticeably slower than the
            // regular scan. Set expectations.
            Text("A whole batch takes a little while — usually under a minute.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            backgroundOrCancelButtons
        }
        .padding(Theme.Spacing.xl)
    }

    /// Shared bottom actions for both progress stages — same pattern as the
    /// scan flow: continuing in the background is the encouraged path,
    /// cancelling the quiet escape hatch.
    private var backgroundOrCancelButtons: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button("Continue in Background") { runner.minimizeFlow() }
                .buttonStyle(SoftButtonStyle())
            Button("Cancel") { runner.cancelRun() }
                .buttonStyle(QuietButtonStyle())
        }
    }

    // MARK: - Stage 4: results

    private func resultsList(_ record: AnalysisRecord) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if let result = record.deepVision {
                    DeepVisionResultsView(result: result, previews: runner.previews)
                }

                Text("Saved to History.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }
}
