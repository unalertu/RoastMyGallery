import Foundation
import Observation
import PhotosUI
import SwiftUI

/// App-scoped owner of the hand-picked Deep Vision flow: persona/stats
/// context, the picked photos, and the run itself (downscale → upload →
/// persist). Living here — not in view @State — means the run survives the
/// flow being minimized or the app briefly backgrounded, exactly like the
/// scan pipeline in `ScanViewModel`: `RootView` presents the one
/// `DeepVisionFlowView` cover off `isFlowPresented`, `AnalysisStatusBanner`
/// mirrors a minimized run, and `AnalysisNotifier` announces completions
/// from the background.
///
/// PRIVACY: unchanged from the view-owned days — this is (with photo
/// captions) one of only two code paths that upload image data, it runs only
/// on the explicit per-batch consent collected by `DeepVisionFlowView`, and
/// every photo is downscaled first.
@MainActor
@Observable
final class DeepVisionRunner {
    enum Phase: Equatable {
        /// Picking photos / giving consent (or, standalone entry, choosing a
        /// persona first). Also where a failed run lands, with `errorMessage`
        /// set and the selection intact for a one-tap retry.
        case idle
        /// On-device downscale/re-encode of the picked photos.
        case preparing(done: Int, total: Int)
        /// Upload + vision model.
        case analyzing
        /// Persisted to history; the flow shows it from the record.
        case finished(AnalysisRecord)
    }

    private(set) var phase: Phase = .idle
    /// Whether the modal flow is on screen — same hoisted-presentation
    /// pattern as `ScanViewModel.isFlowPresented`; `RootView` owns the cover.
    var isFlowPresented = false

    // MARK: Flow context

    /// Voice for the commentary. Preset when entered from an existing
    /// analysis; chosen on the flow's first screen for the standalone entry.
    var persona: Persona?
    /// Stats persisted alongside the run in History; nil (standalone entry)
    /// falls back to `PhotoStats.handPickedPlaceholder()` at save time.
    private(set) var sourceStats: PhotoStats?
    /// The picked photos. Kept here so a minimized (or failed) flow reopens
    /// with the selection intact.
    var selection: [PhotosPickerItem] = []
    /// Inline error shown on the picking screen after a failed run.
    private(set) var errorMessage: String?
    /// True when the last failure was the backend's authoritative
    /// insufficient-gems rejection — the flow routes it to the paywall.
    private(set) var failureWasInsufficientGems = false
    /// Downscaled images from the last successful run, so results render
    /// instantly without a PhotoKit round-trip. Empty when a finished record
    /// is reopened later (cards then resolve by asset ID, the History path).
    private(set) var previews: [String: UIImage] = [:]

    /// A run that finished while the flow was minimized (see
    /// `AnalysisStatusBanner`); cleared when opened or dismissed.
    private(set) var backgroundCompletion: AnalysisRecord?
    /// Same, for a run that failed while minimized.
    private(set) var backgroundFailureMessage: String?

    var isRunActive: Bool {
        switch phase {
        case .preparing, .analyzing: return true
        default: return false
        }
    }

    var maxBatchSize: Int { service.maxBatchSize }

    private let service: DeepVisionAnalyzing
    private let history: AnalysisHistoryStore
    private let purchaseManager: PurchaseManager
    private var runTask: Task<Void, Never>?

    init(service: DeepVisionAnalyzing, history: AnalysisHistoryStore, purchaseManager: PurchaseManager) {
        self.service = service
        self.history = history
        self.purchaseManager = purchaseManager
    }

    // MARK: - Presentation

    /// Entry point from Home (standalone: no persona yet) and from an
    /// existing analysis (persona + stats preset). Never resets an active
    /// run — it re-presents it instead, the same charge-safety rule as
    /// `ScanViewModel.prepareForNewScan`.
    func beginFlow(persona: Persona? = nil, sourceStats: PhotoStats? = nil) {
        guard !isRunActive else {
            isFlowPresented = true
            return
        }
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        self.persona = persona
        self.sourceStats = sourceStats
        selection = []
        previews = [:]
        errorMessage = nil
        failureWasInsufficientGems = false
        pendingBatch = nil
        phase = .idle
        isFlowPresented = true
    }

    func presentFlow() { isFlowPresented = true }

    /// Dismisses the flow while any active run keeps working (the status
    /// banner takes over) — and the contextual moment to lazily ask for
    /// notification permission, mirroring `ScanViewModel.minimizeFlow`.
    func minimizeFlow() {
        isFlowPresented = false
        if isRunActive {
            Task { await AnalysisNotifier.requestAuthorizationIfNeeded() }
        }
    }

    /// Banner tap on a finished run: jump straight to the saved result.
    func openBackgroundResult() {
        guard let record = backgroundCompletion else { return }
        openResult(record)
    }

    /// Notification-tap entry. Safe on cold launch: the record comes from
    /// history, and `previews` being empty just means the result cards
    /// resolve their photos by asset ID like any History view.
    func openResult(_ record: AnalysisRecord) {
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        AnalysisNotifier.clearDelivered(for: .deepVision)
        if isRunActive {
            isFlowPresented = true
            return
        }
        persona = record.persona
        sourceStats = record.stats
        phase = .finished(record)
        isFlowPresented = true
    }

    /// Banner/notification tap on a failed run: reopen the picking screen,
    /// which still holds the selection and shows `errorMessage` inline.
    func reopenFailedRun() {
        backgroundFailureMessage = nil
        AnalysisNotifier.clearDelivered(for: .deepVision)
        isFlowPresented = true
    }

    /// The small ✕ on the banner: acknowledge without opening anything.
    func dismissBackgroundNotice() {
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        AnalysisNotifier.clearDelivered(for: .deepVision)
    }

    // MARK: - Run

    /// Runs the batch: load + downscale on device, one consented upload,
    /// persist to History. Caller (the flow view) has verified affordability
    /// and collected the per-batch consent toggle.
    func submit(appUserID: String) {
        guard runTask == nil, let persona else { return }
        let items = selection
        guard !items.isEmpty else { return }
        errorMessage = nil
        failureWasInsufficientGems = false
        let runID = runID(for: items, persona: persona)
        let stats = sourceStats ?? .handPickedPlaceholder()

        runTask = Task {
            let keepAlive = BackgroundKeepAlive(name: "deep-vision-run")
            defer {
                runTask = nil
                keepAlive.end()
            }
            do {
                phase = .preparing(done: 0, total: items.count)
                var photos: [(assetID: String, jpegData: Data)] = []
                var freshPreviews: [String: UIImage] = [:]
                let budget = ImageDownscaler.perPhotoBudget(batchSize: items.count)

                for (index, item) in items.enumerated() {
                    try Task.checkCancellation()
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
                    appUserID: appUserID,
                    runID: runID
                )

                // The backend deducted the 5 gems (deduct-after-success);
                // reflect the spend locally right away (and survive read-
                // after-write lag on the balance re-read — see `reflectSpend`).
                await purchaseManager.reflectSpend(PurchaseManager.deepVisionCost)

                previews = freshPreviews
                let record = makeRecord(result: result, persona: persona, stats: stats)
                history.add(record)
                phase = .finished(record)
                runFinished(with: record)
            } catch is CancellationError {
                phase = .idle
            } catch let error as DeepVisionError {
                failureWasInsufficientGems = error == .insufficientGems
                runFailed(message: error.localizedDescription)
            } catch {
                runFailed(message: error.localizedDescription)
            }
        }
    }

    /// Always safe to call — stops the batch mid-run; nothing was charged
    /// (deduct-after-success) and the selection stays for another go.
    func cancelRun() {
        runTask?.cancel()
    }

    // MARK: - Charge idempotency

    /// One submitted batch "intent": same photos + same persona = same run ID,
    /// so a retry after a lost response reuses the ID and the backend refuses
    /// to deduct twice (see backend/lib/idempotency.js). In-memory only — the
    /// picker selection can't survive a relaunch anyway.
    private struct PendingBatch {
        let id: UUID
        let itemIDs: [String?]
        let persona: Persona
    }

    private var pendingBatch: PendingBatch?

    private func runID(for items: [PhotosPickerItem], persona: Persona) -> UUID {
        let ids = items.map(\.itemIdentifier)
        if let pending = pendingBatch, pending.itemIDs == ids, pending.persona == persona {
            return pending.id
        }
        let fresh = PendingBatch(id: UUID(), itemIDs: ids, persona: persona)
        pendingBatch = fresh
        return fresh.id
    }

    // MARK: - Completion

    private func runFinished(with record: AnalysisRecord) {
        pendingBatch = nil
        if !isFlowPresented { backgroundCompletion = record }
        AnalysisNotifier.notifyCompletionIfBackgrounded(record, flow: .deepVision)
    }

    /// Failure lands back on the picking screen (selection intact, error
    /// inline) rather than a dead-end screen — retry is one tap.
    private func runFailed(message: String) {
        errorMessage = message
        phase = .idle
        if !isFlowPresented { backgroundFailureMessage = message }
        AnalysisNotifier.notifyFailureIfBackgrounded(flow: .deepVision)
    }

    // MARK: - Helpers

    /// Downscale off the main actor — CGImageSource work shouldn't block UI.
    private func downscaled(_ data: Data, budget: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            ImageDownscaler.uploadJPEG(from: data, budgetBytes: budget)
        }.value
    }

    /// Persist the run as its own History entry, marked by `deepVision` being
    /// set. The synthesized `Insight` keeps older render paths (rows, share
    /// cards) working; stats are inherited from the source analysis.
    private func makeRecord(result: DeepVisionResult, persona: Persona, stats: PhotoStats) -> AnalysisRecord {
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
        return AnalysisRecord(
            id: UUID(),
            createdAt: .now,
            persona: persona,
            insight: insight,
            stats: stats,
            categoryPhotoIndex: nil,
            deepVision: result
        )
    }
}
