import SwiftUI
import PhotosUI

/// Screen 6 — Pro-tier flow: user hand-picks up to 30 photos, sees an
/// explicit, plainly-worded consent notice that THESE photos will be
/// uploaded, and confirms per batch. Calm, no dark patterns: consent is an
/// unchecked opt-in every time, and the primary button stays disabled
/// until it's given.
///
/// This is the only place in the app that can trigger an image upload.
/// Every picked photo is downscaled/re-encoded first (`ImageDownscaler`) —
/// full-resolution originals never leave the device.
///
/// Credits: the flow is entered through a UX-only affordability gate
/// (`InsightView`), re-checked here before upload. The actual 5-credit charge
/// is issued by the backend AFTER a successful batch — a failed run never
/// costs anything.
struct DeepAnalysisConsentView: View {
    /// Voice for the commentary.
    let persona: Persona
    /// Stats persisted alongside the run in History. For a run launched from an
    /// existing analysis this is that analysis's stats; for the standalone
    /// Hand-Picked entry it's `PhotoStats.handPickedPlaceholder()` (there was
    /// no scan — the insight comes entirely from the uploaded photos).
    let sourceStats: PhotoStats

    /// Injectable for previews/tests; live by default.
    var service: DeepVisionAnalyzing = BackendDeepVisionService()

    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AnalysisHistoryStore.self) private var history

    private enum Phase: Equatable {
        case picking
        case preparing(done: Int, total: Int)
        case analyzing
        case finished(DeepVisionResult)
    }

    @State private var selection: [PhotosPickerItem] = []
    @State private var hasConsented = false
    @State private var phase: Phase = .picking
    @State private var errorMessage: String?
    @State private var showPaywall = false
    /// Downscaled images from this run, so the results render instantly
    /// without a PhotoKit round-trip (History resolves by asset ID instead).
    @State private var previews: [String: UIImage] = [:]

    private var maxPhotos: Int { service.maxBatchSize }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    switch phase {
                    case .picking:
                        pickerAndConsent
                    case .preparing(let done, let total):
                        preparingProgress(done: done, total: total)
                    case .analyzing:
                        analyzingProgress
                    case .finished(let result):
                        resultsList(result)
                    }
                }
                .transition(.opacity)
            }
            .animation(Theme.motion, value: phase)
            .navigationTitle("Deep Vision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .analyzing ? "Cancel" : "Close") { dismiss() }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .foregroundStyle(Theme.Colors.textPrimary)
        .interactiveDismissDisabled(phase == .analyzing)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .deepVision(have: purchaseManager.creditBalance))
        }
    }

    // MARK: - Phase 1: pick + consent

    private var pickerAndConsent: some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.s) {
                Text("A closer look")
                    .font(Theme.Typography.title)
                Text("Pick up to \(maxPhotos) photos for individual, photo-by-photo commentary.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Theme.Typography.bodyLineSpacing)
            }
            .padding(.top, Theme.Spacing.l)

            PhotosPicker(
                selection: $selection,
                maxSelectionCount: maxPhotos,
                matching: .images
            ) {
                Label(
                    selection.isEmpty
                        ? "Choose Photos"
                        : "\(selection.count) of \(maxPhotos) selected",
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
                    Text("The \(selection.count) photos you picked — and only those — will be resized on your device, uploaded once, and read by an AI service. Nothing else ever leaves your device, and nothing is stored on the server.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(2)
                }
            }
            .tint(Theme.Colors.accent)
            .themedCard()
            .disabled(selection.isEmpty)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit() }
            } label: {
                Text("Analyze These Photos · \(PurchaseManager.deepVisionCost) credits")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selection.isEmpty || !hasConsented)
        }
        .padding(Theme.Spacing.l)
    }

    // MARK: - Phase 2: on-device preparation (downscale/compress)

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
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Phase 3: upload + vision model

    private var analyzingProgress: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()

            DriftingRing()

            VStack(spacing: Theme.Spacing.s) {
                Text("Reading your photos")
                    .font(Theme.Typography.title)
                Text("In your \(persona.displayName.lowercased()) voice…")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            // Multiple images + a vision model: noticeably slower than the
            // regular scan. Set expectations.
            Text("A whole batch takes a little while — usually under a minute.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Theme.Spacing.xl)
    }

    // MARK: - Phase 4: results

    private func resultsList(_ result: DeepVisionResult) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                DeepVisionResultsView(result: result, previews: previews)

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

    // MARK: - Flow

    private func submit() async {
        errorMessage = nil

        // UX-only affordability re-check (the balance may have changed since
        // this sheet opened); the backend/RevenueCat is the real authority.
        guard purchaseManager.canAfford(PurchaseManager.deepVisionCost) else {
            showPaywall = true
            return
        }

        let items = selection
        phase = .preparing(done: 0, total: items.count)
        do {
            var photos: [(assetID: String, jpegData: Data)] = []
            var freshPreviews: [String: UIImage] = [:]
            let budget = ImageDownscaler.perPhotoBudget(batchSize: items.count)

            for (index, item) in items.enumerated() {
                // A photo that fails to load/decode is skipped, not fatal —
                // the batch goes on with the rest.
                if let original = try? await item.loadTransferable(type: Data.self),
                   let jpeg = await downscaled(original, budget: budget) {
                    // PhotosPickerItem.itemIdentifier is only set with photo
                    // library authorization (granted for the scan); fall back
                    // to a local UUID so mapping still works — such photos
                    // just render text-only from History.
                    let assetID = item.itemIdentifier ?? UUID().uuidString
                    photos.append((assetID: assetID, jpegData: jpeg))
                    if let image = UIImage(data: jpeg) { freshPreviews[assetID] = image }
                }
                phase = .preparing(done: index + 1, total: items.count)
            }
            guard !photos.isEmpty else { throw DeepVisionError.preparationFailed }

            phase = .analyzing
            let result = try await service.analyze(
                photos: photos,
                persona: persona,
                appUserID: purchaseManager.appUserID
            )

            // The backend deducted the 5 credits (deduct-after-success);
            // reflect the spend locally right away (and survive read-after-
            // write lag on the balance re-read — see `reflectSpend`).
            await purchaseManager.reflectSpend(PurchaseManager.deepVisionCost)

            previews = freshPreviews
            save(result)
            phase = .finished(result)
        } catch is CancellationError {
            phase = .picking
        } catch let error as DeepVisionError {
            errorMessage = error.localizedDescription
            if error == .insufficientCredits { showPaywall = true }
            phase = .picking
        } catch {
            errorMessage = error.localizedDescription
            phase = .picking
        }
    }

    /// Downscale off the main actor — CGImageSource work shouldn't block UI.
    private func downscaled(_ data: Data, budget: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            ImageDownscaler.uploadJPEG(from: data, budgetBytes: budget)
        }.value
    }

    /// Persist the run as its own History entry, marked by `deepVision` being
    /// set. The synthesized `Insight` keeps older render paths (rows, share
    /// cards) working; stats are inherited from the source analysis.
    private func save(_ result: DeepVisionResult) {
        let insight = Insight(
            id: UUID(),
            persona: persona,
            generatedAt: .now,
            headline: persona == .roast ? "Your Picks, Roasted Up Close" : "Your Picks, Up Close",
            body: ([result.summary] + result.segments.map(\.text)).joined(separator: "\n\n"),
            segments: nil,
            shareLine: result.summary,
            superlatives: []
        )
        history.add(
            AnalysisRecord(
                id: UUID(),
                createdAt: .now,
                persona: persona,
                insight: insight,
                stats: sourceStats,
                categoryPhotoIndex: nil,
                deepVision: result
            )
        )
    }
}
