import Foundation
import Photos
import Observation

/// Drives the modal scan flow: permission → persona pick → scan → aggregate →
/// LLM insight → results. Owns the pipeline services (via `AppEnvironment`)
/// and exposes a single `phase` that `ScanFlowView` switches on.
///
/// Completed runs are saved to `AnalysisHistoryStore` before entering
/// `.results`, so Home/History reflect the new analysis even if the user
/// closes the flow immediately.
@MainActor
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case needsPermission
        case permissionDenied
        case readyToScan
        case scanning(AnalysisProgress)
        case generatingInsight
        /// Deep analysis only: the pipeline is PAUSED showing the user the exact
        /// photos that would be uploaded for captions, waiting for them to
        /// approve (or trim, or refuse) that batch. Carries the asset IDs in
        /// results order. Nothing has left the device at this point.
        case reviewingCaptionPhotos([String])
        /// Deep analysis only: uploading the approved photos for their
        /// per-photo captions (best-effort — never fails the run).
        case captioning
        case results(AnalysisRecord)
        case failed(message: String)
    }

    private(set) var phase: Phase = .needsPermission
    /// Whether the modal scan flow is on screen. Hoisted here (instead of
    /// view-local @State) so every surface can present it: Home's buttons,
    /// the status banner, a completion-notification tap. `RootView` owns the
    /// one `fullScreenCover` bound to this; `dismiss()` inside the flow flips
    /// it back through that binding.
    var isFlowPresented = false
    /// A run that finished while the flow was minimized, waiting to be seen.
    /// Drives the "ready" state of `AnalysisStatusBanner`; cleared when the
    /// user opens the result, dismisses the banner, or starts a new scan.
    private(set) var backgroundCompletion: AnalysisRecord?
    /// Same, for a run that failed while minimized.
    private(set) var backgroundFailureMessage: String?

    /// True while the pipeline is actually working (scan → insight → captions).
    /// The minimized-run banner keys off this.
    ///
    /// Deliberately EXCLUDES `.reviewingCaptionPhotos`: nothing is progressing
    /// while we wait for the user, so the banner must not claim otherwise and
    /// the flow's close button must cancel rather than minimize — minimizing a
    /// run that can only advance on a tap would suspend it forever.
    var isRunActive: Bool {
        switch phase {
        case .scanning, .generatingInsight, .captioning: return true
        default: return false
        }
    }

    /// Paused mid-run on the caption-approval gate. Not `isRunActive` (see
    /// above), but it still owns the pipeline, so a new run must not start on
    /// top of it — the "don't clobber a paid run" guards check both.
    var isAwaitingCaptionReview: Bool {
        if case .reviewingCaptionPhotos = phase { return true }
        return false
    }
    /// No default on purpose — the picker presents both personas neutrally
    /// and the user must choose before scanning.
    var selectedPersona: Persona?
    /// Starts at full history as an internal placeholder, but every tier now
    /// requires an explicit scope before scanning (standard: a month or album;
    /// deep: a date range) — the picker's CTA stays disabled until one is set.
    var selectedScope: AnalysisScope = .fullHistory
    /// Chosen on Home's "New Analysis" product cards, before the flow presents.
    var selectedDepth: AnalysisDepth = .standard
    /// Deep analysis uploads the displayed photos for captioning, so it
    /// requires this explicit opt-in every run (see PersonaPickerView's
    /// consent card). Standard scans ignore it — they never upload photos.
    var hasDeepConsent = false

    private let environment: AppEnvironment
    private let history: AnalysisHistoryStore
    private let purchaseManager: PurchaseManager
    private var scanTask: Task<Void, Never>?

    init(environment: AppEnvironment, history: AnalysisHistoryStore, purchaseManager: PurchaseManager) {
        self.environment = environment
        self.history = history
        self.purchaseManager = purchaseManager
        refreshPermissionPhase()
    }

    // MARK: - Flow lifecycle

    /// Called when the scan flow is presented: clears any previous run so the
    /// flow always starts at permission/persona choice.
    /// - Parameter depth: chosen on Home's "New Analysis" product cards. Deep
    ///   starts scope-less (the user must pick a date range) and with consent
    ///   reset — it's an explicit opt-in every run.
    func prepareForNewScan(depth: AnalysisDepth = .standard) {
        // A run is already working — or paused waiting for caption approval:
        // never cancel-and-reset it from the New Analysis entry points, surface
        // it instead. Charges are deduct-after-success, so cancelling a
        // nearly-done run and starting fresh is exactly how you'd pay twice for
        // one story.
        guard !isRunActive, !isAwaitingCaptionReview else {
            isFlowPresented = true
            return
        }
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        cancelScan()
        selectedPersona = nil
        selectedScope = .fullHistory
        selectedDepth = depth
        hasDeepConsent = false
        phase = .needsPermission
        refreshPermissionPhase()
    }

    /// Albums available for the album-scoped analysis mode.
    func fetchAlbums() -> [PhotoLibraryService.AlbumInfo] {
        environment.photoLibrary.fetchUserAlbums()
    }

    /// Whether the user granted *limited* photo access. Album-scoped analysis
    /// can't enumerate album contents under limited access — PhotoKit only
    /// exposes the hand-picked selection, so every album reads as empty — so
    /// the album picker uses this to steer the user to Full Access rather than
    /// showing a misleading "no albums" list.
    var isLimitedPhotoAccess: Bool {
        environment.photoLibrary.currentAuthorizationStatus() == .limited
    }

    // MARK: - Presentation

    func presentFlow() { isFlowPresented = true }

    /// Dismisses the flow while any active run keeps working (the status
    /// banner takes over). Also the moment we lazily ask for notification
    /// permission — the user just expressed "tell me later", so the prompt
    /// has context. Never re-prompts once decided.
    func minimizeFlow() {
        isFlowPresented = false
        if isRunActive {
            Task { await AnalysisNotifier.requestAuthorizationIfNeeded() }
        }
    }

    /// Banner tap on a finished run: jump straight to the saved result.
    func openBackgroundResult() {
        guard let record = backgroundCompletion else { return }
        openResult(withID: record.id)
    }

    /// Banner tap on a failed run: reopen the flow on its failure screen
    /// (the phase still holds `.failed`, so Try Again is right there).
    func reopenFailedRun() {
        backgroundFailureMessage = nil
        isFlowPresented = true
    }

    /// The small ✕ on the banner: acknowledge without opening anything.
    func dismissBackgroundNotice() {
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        AnalysisNotifier.clearDelivered(for: .scan)
    }

    /// Entry point for completion-notification taps. Safe on cold launch,
    /// where the phase machine knows nothing about the tapped record — it's
    /// looked up in history (already persisted before the notification could
    /// have been posted) instead.
    func openResult(withID id: UUID?) {
        backgroundCompletion = nil
        backgroundFailureMessage = nil
        AnalysisNotifier.clearDelivered(for: .scan)
        // A newer run is in flight — show it rather than clobbering its phase.
        if isRunActive {
            isFlowPresented = true
            return
        }
        if let record = id.flatMap({ tapped in history.records.first { $0.id == tapped } }) {
            phase = .results(record)
            isFlowPresented = true
        } else if case .failed = phase {
            // A failure notification carries no record ID — reopen the flow
            // on its failure screen so Try Again is one tap away.
            isFlowPresented = true
        }
    }

    // MARK: - Permission

    /// Re-derives the permission-related phase without clobbering an active
    /// scan or finished results (e.g. when returning from Settings).
    func refreshPermissionPhase() {
        switch environment.photoLibrary.currentAuthorizationStatus() {
        case .authorized, .limited:
            if phase == .needsPermission || phase == .permissionDenied {
                phase = .readyToScan
            }
        case .denied, .restricted:
            if phase == .needsPermission || phase == .readyToScan {
                phase = .permissionDenied
            }
        case .notDetermined:
            if phase == .permissionDenied { phase = .needsPermission }
        @unknown default:
            break
        }
    }

    func requestPermission() async {
        let status = await environment.photoLibrary.requestAuthorization()
        switch status {
        case .authorized, .limited:
            phase = .readyToScan
        default:
            phase = .permissionDenied
        }
    }

    // MARK: - Charge idempotency

    /// One analysis "intent": the parameters that identify a run for charge
    /// purposes, plus the run ID the backend dedupes deductions on. Persisted
    /// (UserDefaults) so a retry after the app was suspended or killed still
    /// reuses the same ID — that persistence is what closes the last
    /// double-charge window: a response lost after the server-side deduction
    /// is retried under the same ID, and the backend refuses to charge it
    /// again (see backend/lib/idempotency.js).
    private struct PendingRun: Codable {
        let id: UUID
        let scope: AnalysisScope
        let persona: Persona
        let depth: AnalysisDepth
        let variationSeed: Int

        /// Same intent = same everything except the ID itself.
        func matches(_ other: PendingRun) -> Bool {
            scope == other.scope && persona == other.persona
                && depth == other.depth && variationSeed == other.variationSeed
        }
    }

    private static let pendingRunDefaultsKey = "pendingInsightRun"

    /// Returns the charge-idempotency ID for this exact intent: the stored
    /// one when retrying the same run, a fresh UUID (persisted) otherwise.
    private func runID(
        scope: AnalysisScope,
        persona: Persona,
        depth: AnalysisDepth,
        variationSeed: Int
    ) -> UUID {
        let intent = PendingRun(
            id: UUID(),
            scope: scope,
            persona: persona,
            depth: depth,
            variationSeed: variationSeed
        )
        if let data = UserDefaults.standard.data(forKey: Self.pendingRunDefaultsKey),
           let stored = try? JSONDecoder.backend.decode(PendingRun.self, from: data),
           stored.matches(intent) {
            return stored.id
        }
        if let data = try? JSONEncoder.backend.encode(intent) {
            UserDefaults.standard.set(data, forKey: Self.pendingRunDefaultsKey)
        }
        return intent.id
    }

    /// The run completed (and was charged at most once under its ID) — the
    /// next run of the same parameters is a new intent and must pay again.
    private func clearPendingRun() {
        UserDefaults.standard.removeObject(forKey: Self.pendingRunDefaultsKey)
    }

    // MARK: - Scan pipeline

    /// Runs the full pipeline over `selectedScope` (full history by default,
    /// or a date range / album for the scoped modes). Costs 1 gem,
    /// deducted by the backend *after* a successful insight (see
    /// `BackendInsightGenerator`) — the scope itself doesn't change the cost.
    ///
    /// - Parameter appUserID: RevenueCat App User ID, forwarded to the backend
    ///   so it can charge the right customer. Caller should have already
    ///   verified affordability (UX gate) before invoking this.
    func startScan(appUserID: String) {
        guard scanTask == nil, let persona = selectedPersona else { return }
        let scope = selectedScope
        let depth = selectedDepth

        // Deep analysis uploads the displayed photos for captioning, so the
        // per-run consent toggle is a hard precondition (the UI enforces this
        // too; this guard is the backstop).
        if depth == .deep {
            guard hasDeepConsent else { return }
        }

        // Free re-open: a bounded scope (a past month, a specific album) we've
        // already analyzed with this persona AT THIS DEPTH is effectively
        // immutable, so show the saved insight instead of re-scanning and
        // charging again. The Regenerate action on the results screen is the
        // paid "fresh take". Depth must match: a cached standard record must
        // never satisfy (and short-change) a deep request, or vice versa.
        if scope.isCacheable, let cached = cachedRecord(scope: scope, persona: persona, depth: depth) {
            phase = .results(cached)
            return
        }

        scanTask = Task {
            let keepAlive = BackgroundKeepAlive(name: "analysis-run")
            defer {
                scanTask = nil
                keepAlive.end()
            }
            do {
                phase = .scanning(AnalysisProgress(completed: 0, total: 0))

                let scan = try await environment.analyzer.analyze(scope: scope) { progress in
                    Task { @MainActor [weak self] in
                        // Only update while still scanning; late callbacks are dropped.
                        if case .scanning = self?.phase {
                            self?.phase = .scanning(progress)
                        }
                    }
                }

                let stats = environment.aggregator.aggregate(
                    scan.observations,
                    totalPhotos: scan.totalAssets,
                    scope: scope,
                    depth: depth
                )
                // Device-only side map (category → asset IDs) so the results
                // screen can show a photo next to matching insight segments.
                let photoIndex = environment.aggregator.photoIndex(for: scan.observations)

                phase = .generatingInsight
                let insight = try await environment.insightGenerator.generateInsight(
                    from: stats,
                    persona: persona,
                    appUserID: appUserID,
                    variationSeed: 0,
                    depth: depth,
                    runID: runID(scope: scope, persona: persona, depth: depth, variationSeed: 0)
                )

                // The backend just charged for this insight (deduct-after-
                // success, 1 CRD standard / 5 CRD deep). Reflect it locally now
                // so Home/Settings show the drop immediately — a cache re-open
                // above returns before here and is never charged.
                await purchaseManager.reflectSpend(PurchaseManager.cost(for: depth))

                // Persist the story NOW, before the caption step. It is already
                // written and already charged for, and the approval gate below
                // waits on a human — so the app being killed while that gate is
                // on screen must not take a paid story with it. Captions are
                // folded in afterwards via `history.update`.
                var record = AnalysisRecord(
                    id: UUID(),
                    createdAt: .now,
                    persona: persona,
                    insight: insight,
                    stats: stats,
                    categoryPhotoIndex: photoIndex,
                    depth: depth,
                    photoCaptions: nil
                )
                history.add(record)

                // Deep only: caption the photos the results screen will show.
                // Best-effort throughout — a refusal, a hiccup or a cancel here
                // collapses to "no captions" and never costs the story.
                if depth == .deep, let segments = insight.segments, !segments.isEmpty {
                    let targets = captionTargets(segments: segments, photoIndex: photoIndex)
                    if !targets.isEmpty {
                        // THE UPLOAD GATE. The app picks which photos illustrate
                        // the story, so the user has to see that exact batch
                        // before any of it leaves the device — anything else
                        // would be asking them to consent to a set neither of
                        // us could name at consent time.
                        let approved = await awaitCaptionApproval(
                            candidates: targets.map(\.assetID)
                        )
                        if let approved, !approved.isEmpty {
                            phase = .captioning
                            let approvedIDs = Set(approved)
                            if let captions = await uploadCaptions(
                                for: targets.filter { approvedIDs.contains($0.assetID) },
                                persona: persona,
                                appUserID: appUserID
                            ) {
                                record.photoCaptions = captions
                                history.update(record)
                            }
                        }
                    }
                }

                phase = .results(record)
                runFinished(with: record)
            } catch is CancellationError {
                phase = .readyToScan
            } catch {
                let message = error.localizedDescription
                phase = .failed(message: message)
                runFailed(message: message)
            }
        }
    }

    // MARK: - Background completion

    /// A run just produced (and persisted) a record. If the flow is minimized,
    /// arm the in-app "ready" banner; if the whole app is backgrounded, also
    /// post a local notification so the user hears about it from outside.
    private func runFinished(with record: AnalysisRecord) {
        clearPendingRun()
        // Counted here (real completions only) so the results screen's
        // automatic rating prompt never triggers off a free cache re-open.
        ReviewPrompter.recordCompletedRun()
        if !isFlowPresented { backgroundCompletion = record }
        AnalysisNotifier.notifyCompletionIfBackgrounded(record)
    }

    private func runFailed(message: String) {
        if !isFlowPresented { backgroundFailureMessage = message }
        AnalysisNotifier.notifyFailureIfBackgrounded()
    }

    // MARK: - Caption approval gate

    /// Resumes the paused pipeline once the user decides on the caption batch.
    /// Non-throwing on purpose: a cancellation resolves to `nil` ("send
    /// nothing") rather than throwing, because the long story has already been
    /// generated and charged for and must still be saved.
    private var captionReviewContinuation: CheckedContinuation<[String]?, Never>?

    /// Upload captions for these photos — the full candidate batch, or whatever
    /// subset the user left selected.
    func approveCaptionPhotos(_ assetIDs: [String]) {
        resumeCaptionReview(with: assetIDs)
    }

    /// Send nothing. The story is kept and saved; it simply has no captions.
    func skipCaptionPhotos() {
        resumeCaptionReview(with: nil)
    }

    /// Idempotent: the continuation is cleared BEFORE it is resumed, so a
    /// cancellation racing a button tap can't resume the same continuation
    /// twice (which traps at runtime).
    private func resumeCaptionReview(with assetIDs: [String]?) {
        guard let continuation = captionReviewContinuation else { return }
        captionReviewContinuation = nil
        continuation.resume(returning: assetIDs)
    }

    /// Shows the batch and suspends until the user answers. Returns the asset
    /// IDs to upload, or nil to upload nothing.
    private func awaitCaptionApproval(candidates: [String]) async -> [String]? {
        phase = .reviewingCaptionPhotos(candidates)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Already cancelled before we could store it — resolve right
                // here, or the handler below would have nothing to resume and
                // the run would hang forever.
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    captionReviewContinuation = continuation
                }
            }
        } onCancel: {
            // Closing the flow cancels the task; treat that as "send nothing"
            // so the pipeline resumes, saves the story, and finishes cleanly.
            Task { @MainActor in self.resumeCaptionReview(with: nil) }
        }
    }

    /// The photos the results screen will show, one per segment, de-duplicated
    /// and capped at the upload batch size — i.e. EXACTLY the batch that would
    /// be uploaded. Pure and side-effect free, so the review screen and the
    /// upload can never disagree about what is being sent.
    private func captionTargets(
        segments: [Insight.Segment],
        photoIndex: [String: [String]]?
    ) -> [(assetID: String, segmentText: String, category: String?)] {
        let perSegment = SegmentPhotoResolver.assetIDsPerSegment(
            segments: segments,
            photoIndex: photoIndex
        )

        // One photo per segment (its displayed candidate), de-duplicated —
        // a photo reused by two beats gets one caption, keyed by asset ID.
        var targets: [(assetID: String, segmentText: String, category: String?)] = []
        var seen: Set<String> = []
        for (index, segment) in segments.enumerated() {
            guard let assetID = perSegment[index].first, seen.insert(assetID).inserted else { continue }
            targets.append((assetID, segment.text, segment.category))
        }
        return Array(targets.prefix(environment.photoCaptions.maxBatchSize))
    }

    /// Downscales the approved photos and asks the backend for one caption
    /// each. Returns asset ID → caption, or nil when nothing could be
    /// captioned — by design this can only *add* to the results, never fail
    /// them.
    private func uploadCaptions(
        for targets: [(assetID: String, segmentText: String, category: String?)],
        persona: Persona,
        appUserID: String
    ) async -> [String: String]? {
        guard !targets.isEmpty else { return nil }
        let photos = await CaptionPhotoLoader.loadJPEGs(for: targets)
        guard !photos.isEmpty else { return nil }

        do {
            let captions = try await environment.photoCaptions.captions(
                for: photos,
                persona: persona,
                appUserID: appUserID
            )
            var byAssetID: [String: String] = [:]
            for (photo, caption) in zip(photos, captions) where !caption.isEmpty {
                byAssetID[photo.assetID] = caption
            }
            return byAssetID.isEmpty ? nil : byAssetID
        } catch {
            // Includes cancellation: the story is already paid for and the
            // caller persists it regardless.
            return nil
        }
    }

    /// Always safe to call — the flow's Close button uses this so the user
    /// can back out mid-scan without losing the app.
    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Regenerate

    /// Paid "fresh take" on an existing analysis. Re-runs ONLY the insight
    /// generation over the record's already-computed `stats` — no re-scan, no
    /// new Vision work — with an advancing `variationSeed` so the backend
    /// rotates the narrative lens and the result reads differently. Costs 1
    /// gem via the backend's deduct-after-success, exactly like a normal
    /// analysis. Caller should have verified affordability (UX gate) first.
    ///
    /// Drives `phase` (generatingInsight → results) so both presentation
    /// contexts work: inside the scan flow it transitions in place; from
    /// Home/History the caller presents `ScanFlowView` to observe the phase.
    func regenerate(from record: AnalysisRecord, appUserID: String) {
        guard scanTask == nil else { return }
        // A deep record regenerates deep (long story, 5 gems — the backend
        // charges by the depth it writes at); standard regenerates for 1.
        let depth = record.depth ?? .standard

        // The progress screen reads selectedDepth/selectedPersona for its
        // copy ("Writing your long story", "In your roast voice…"). A
        // regenerate can start from Home/History with stale values left by
        // an earlier flow, so sync them to the record being regenerated.
        selectedDepth = depth
        selectedPersona = record.persona

        // Seed = how many insights already exist for this exact scope+persona,
        // so the first Regenerate is 1, the next 2, … and lenses rotate.
        let seed = history.records.filter {
            $0.persona == record.persona && $0.stats.scope == record.stats.scope
        }.count

        scanTask = Task {
            let keepAlive = BackgroundKeepAlive(name: "regenerate-run")
            defer {
                scanTask = nil
                keepAlive.end()
            }
            do {
                phase = .generatingInsight
                let insight = try await environment.insightGenerator.generateInsight(
                    from: record.stats,
                    persona: record.persona,
                    appUserID: appUserID,
                    variationSeed: seed,
                    depth: depth,
                    runID: runID(
                        scope: record.stats.scope,
                        persona: record.persona,
                        depth: depth,
                        variationSeed: seed
                    )
                )

                // A fresh take is charged like any analysis (1 CRD standard /
                // 5 CRD deep) — reflect the spend as soon as it succeeds.
                await purchaseManager.reflectSpend(PurchaseManager.cost(for: depth))

                // A fresh narrative over the same stats/photos. Deep Vision (a
                // separate paid, photo-level action) is intentionally not
                // carried over — the original record keeps it in history.
                // Photo captions ARE carried (keyed by asset ID): consent was
                // per-run, so no re-upload happens here — photos the fresh
                // beats reuse keep their captions, newly surfaced ones simply
                // have none.
                let fresh = AnalysisRecord(
                    id: UUID(),
                    createdAt: .now,
                    persona: record.persona,
                    insight: insight,
                    stats: record.stats,
                    categoryPhotoIndex: record.categoryPhotoIndex,
                    deepVision: nil,
                    depth: record.depth,
                    photoCaptions: record.photoCaptions
                )
                history.add(fresh)
                phase = .results(fresh)
                runFinished(with: fresh)
            } catch is CancellationError {
                // Fall back to the analysis they started from.
                phase = .results(record)
            } catch {
                let message = error.localizedDescription
                phase = .failed(message: message)
                runFailed(message: message)
            }
        }
    }

    /// Newest saved analysis matching an exact scope + persona + depth, if any.
    private func cachedRecord(scope: AnalysisScope, persona: Persona, depth: AnalysisDepth) -> AnalysisRecord? {
        history.records.first {
            $0.persona == persona && $0.stats.scope == scope && ($0.depth ?? .standard) == depth
        }
    }

    /// Retry after failure. Keeps the chosen persona so retrying is one tap.
    func reset() {
        cancelScan()
        phase = .readyToScan
        refreshPermissionPhase()
    }
}
