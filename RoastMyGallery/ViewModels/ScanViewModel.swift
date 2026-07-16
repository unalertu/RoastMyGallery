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
        /// Deep analysis only: uploading the results-screen photos for their
        /// per-photo captions (best-effort — never fails the run).
        case captioning
        case results(AnalysisRecord)
        case failed(message: String)
    }

    private(set) var phase: Phase = .needsPermission
    /// No default on purpose — the picker presents both personas neutrally
    /// and the user must choose before scanning.
    var selectedPersona: Persona?
    /// Starts at full history as an internal placeholder, but every tier now
    /// requires an explicit scope before scanning (standard: a month or album;
    /// deep: a date range) — the picker's CTA stays disabled until one is set.
    var selectedScope: AnalysisScope = .fullHistory
    /// Chosen on the "New Analysis" options sheet, before the flow presents.
    var selectedDepth: AnalysisDepth = .standard
    /// Deep analysis uploads the displayed photos for captioning, so it
    /// requires this explicit opt-in every run (see PersonaPickerView's
    /// consent card). Standard scans ignore it — they never upload photos.
    var hasDeepConsent = false

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
    /// - Parameter depth: chosen on the "New Analysis" options sheet. Deep
    ///   starts scope-less (the user must pick a date range) and with consent
    ///   reset — it's an explicit opt-in every run.
    func prepareForNewScan(depth: AnalysisDepth = .standard) {
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

    /// TEMP DIAGNOSTIC — human-readable current photo authorization, surfaced
    /// on the album picker's empty state so we can confirm full-vs-limited
    /// access on-device without the console. Remove once the album picker bug
    /// is understood.
    var photoAccessDebugDescription: String {
        switch environment.photoLibrary.currentAuthorizationStatus() {
        case .authorized: return "authorized (full)"
        case .limited: return "limited"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
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
                    depth: depth
                )

                // Deep only: caption the photos the results screen will show.
                // Best-effort — the 5 credits bought the long story above; a
                // captioning hiccup (or a cancel while captioning) must never
                // lose it, so failures collapse to "no captions" and we still
                // persist the record.
                var captions: [String: String]?
                if depth == .deep, let segments = insight.segments, !segments.isEmpty {
                    phase = .captioning
                    captions = await generateCaptions(
                        segments: segments,
                        photoIndex: photoIndex,
                        persona: persona,
                        appUserID: appUserID
                    )
                }

                let record = AnalysisRecord(
                    id: UUID(),
                    createdAt: .now,
                    persona: persona,
                    insight: insight,
                    stats: stats,
                    categoryPhotoIndex: photoIndex,
                    depth: depth,
                    photoCaptions: captions
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

    /// Resolves which photo each segment card will display (via the shared
    /// `SegmentPhotoResolver`, so captions and cards can't drift apart),
    /// downscales those photos, and asks the backend for one caption each.
    /// Returns asset ID → caption, or nil when nothing could be captioned —
    /// by design this can only *add* to the results, never fail them.
    private func generateCaptions(
        segments: [Insight.Segment],
        photoIndex: [String: [String]]?,
        persona: Persona,
        appUserID: String
    ) async -> [String: String]? {
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
        guard !targets.isEmpty else { return nil }

        let batch = Array(targets.prefix(environment.photoCaptions.maxBatchSize))
        let photos = await CaptionPhotoLoader.loadJPEGs(for: batch)
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
    /// credit via the backend's deduct-after-success, exactly like a normal
    /// analysis. Caller should have verified affordability (UX gate) first.
    ///
    /// Drives `phase` (generatingInsight → results) so both presentation
    /// contexts work: inside the scan flow it transitions in place; from
    /// Home/History the caller presents `ScanFlowView` to observe the phase.
    func regenerate(from record: AnalysisRecord, appUserID: String) {
        guard scanTask == nil else { return }
        // A deep record regenerates deep (long story, 5 credits — the backend
        // charges by the depth it writes at); standard regenerates for 1.
        let depth = record.depth ?? .standard

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
                    variationSeed: seed,
                    depth: depth
                )

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
            } catch is CancellationError {
                // Fall back to the analysis they started from.
                phase = .results(record)
            } catch {
                phase = .failed(message: error.localizedDescription)
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
