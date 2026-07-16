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
        case results(AnalysisRecord)
        case failed(message: String)
    }

    private(set) var phase: Phase = .needsPermission
    /// No default on purpose — the picker presents both personas neutrally
    /// and the user must choose before scanning.
    var selectedPersona: Persona?
    /// Defaults to full history so the free/standard flow needs zero extra
    /// taps — scoped modes (date range, album) are opted into explicitly.
    var selectedScope: AnalysisScope = .fullHistory

    private let environment: AppEnvironment
    private let history: AnalysisHistoryStore
    private var scanTask: Task<Void, Never>?

    init(environment: AppEnvironment, history: AnalysisHistoryStore) {
        self.environment = environment
        self.history = history
        refreshPermissionPhase()
    }

    // MARK: - Flow lifecycle

    /// Called when the scan flow is presented: clears any previous run so the
    /// flow always starts at permission/persona choice.
    func prepareForNewScan() {
        cancelScan()
        selectedPersona = nil
        selectedScope = .fullHistory
        phase = .needsPermission
        refreshPermissionPhase()
    }

    /// Albums available for the album-scoped analysis mode.
    func fetchAlbums() -> [PhotoLibraryService.AlbumInfo] {
        environment.photoLibrary.fetchUserAlbums()
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

    // MARK: - Scan pipeline

    /// Runs the full pipeline over `selectedScope` (full history by default,
    /// or a date range / album for the scoped modes). Costs 1 credit,
    /// deducted by the backend *after* a successful insight (see
    /// `BackendInsightGenerator`) — the scope itself doesn't change the cost.
    ///
    /// - Parameter appUserID: RevenueCat App User ID, forwarded to the backend
    ///   so it can charge the right customer. Caller should have already
    ///   verified affordability (UX gate) before invoking this.
    func startScan(appUserID: String) {
        guard scanTask == nil, let persona = selectedPersona else { return }
        let scope = selectedScope

        // Free re-open: a bounded scope (a past month, a specific album) we've
        // already analyzed with this persona is effectively immutable, so show
        // the saved insight instead of re-scanning and charging again. The
        // Regenerate action on the results screen is the paid "fresh take".
        if scope.isCacheable, let cached = cachedRecord(scope: scope, persona: persona) {
            phase = .results(cached)
            return
        }

        scanTask = Task {
            defer { scanTask = nil }
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
                    scope: scope
                )
                // Device-only side map (category → asset IDs) so the results
                // screen can show a photo next to matching insight segments.
                let photoIndex = environment.aggregator.photoIndex(for: scan.observations)

                phase = .generatingInsight
                let insight = try await environment.insightGenerator.generateInsight(
                    from: stats,
                    persona: persona,
                    appUserID: appUserID,
                    variationSeed: 0
                )

                let record = AnalysisRecord(
                    id: UUID(),
                    createdAt: .now,
                    persona: persona,
                    insight: insight,
                    stats: stats,
                    categoryPhotoIndex: photoIndex
                )
                history.add(record)
                phase = .results(record)
            } catch is CancellationError {
                phase = .readyToScan
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
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
    /// credit via the backend's deduct-after-success, exactly like a normal
    /// analysis. Caller should have verified affordability (UX gate) first.
    ///
    /// Drives `phase` (generatingInsight → results) so both presentation
    /// contexts work: inside the scan flow it transitions in place; from
    /// Home/History the caller presents `ScanFlowView` to observe the phase.
    func regenerate(from record: AnalysisRecord, appUserID: String) {
        guard scanTask == nil else { return }

        // Seed = how many insights already exist for this exact scope+persona,
        // so the first Regenerate is 1, the next 2, … and lenses rotate.
        let seed = history.records.filter {
            $0.persona == record.persona && $0.stats.scope == record.stats.scope
        }.count

        scanTask = Task {
            defer { scanTask = nil }
            do {
                phase = .generatingInsight
                let insight = try await environment.insightGenerator.generateInsight(
                    from: record.stats,
                    persona: record.persona,
                    appUserID: appUserID,
                    variationSeed: seed
                )

                // A fresh narrative over the same stats/photos. Deep Vision (a
                // separate paid, photo-level action) is intentionally not
                // carried over — the original record keeps it in history.
                let fresh = AnalysisRecord(
                    id: UUID(),
                    createdAt: .now,
                    persona: record.persona,
                    insight: insight,
                    stats: record.stats,
                    categoryPhotoIndex: record.categoryPhotoIndex,
                    deepVision: nil
                )
                history.add(fresh)
                phase = .results(fresh)
            } catch is CancellationError {
                // Fall back to the analysis they started from.
                phase = .results(record)
            } catch {
                phase = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Newest saved analysis matching an exact scope + persona, if any.
    private func cachedRecord(scope: AnalysisScope, persona: Persona) -> AnalysisRecord? {
        history.records.first { $0.persona == persona && $0.stats.scope == scope }
    }

    /// Retry after failure. Keeps the chosen persona so retrying is one tap.
    func reset() {
        cancelScan()
        phase = .readyToScan
        refreshPermissionPhase()
    }
}
