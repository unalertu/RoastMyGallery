import Foundation

/// One completed analysis run — everything needed to re-display results
/// without re-scanning. Persisted locally by `AnalysisHistoryStore`; never
/// leaves the device.
struct AnalysisRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let persona: Persona
    let insight: Insight
    let stats: PhotoStats

    /// Category → up to two representative asset local identifiers, built
    /// on-device during the scan so insight segments can show a matching photo.
    /// DEVICE-ONLY, like the record itself: asset IDs are never serialized to
    /// the backend (only `stats` is — see the PhotoStats privacy contract).
    /// Optional so records persisted before this field decode as nil.
    var categoryPhotoIndex: [String: [String]]?

    /// Set only on Deep Vision entries: the photo-level commentary from the
    /// consented batch. Its presence is what marks a record as a Deep Vision
    /// run in History (nil = regular stats-based analysis, and records
    /// persisted before this field decode as nil).
    var deepVision: DeepVisionResult?

    /// Which tier produced this record. Optional so records persisted before
    /// depths existed decode as nil (treated as `.standard` everywhere).
    var depth: AnalysisDepth? = nil

    /// Deep analysis only: asset local identifier → the AI's short caption for
    /// that photo, rendered under the matching photo card in the results.
    /// DEVICE-ONLY: built client-side by mapping the caption batch order back
    /// to asset IDs — the IDs themselves are never uploaded.
    var photoCaptions: [String: String]? = nil
}

/// Which of the three purchasable flows produced a record. Not stored as its
/// own field — derived from what each flow already writes (`deepVision` /
/// `depth`), so legacy records classify correctly with no migration: anything
/// saved before tiers existed has both fields nil and reads as `.standard`.
enum AnalysisKind: String, CaseIterable, Identifiable, Sendable {
    /// The classic 1-credit stats analysis.
    case standard
    /// The 5-credit date-range Deep Analysis.
    case deep
    /// The 5-credit hand-picked Deep Vision batch.
    case handPicked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .deep: return "Deep"
        case .handPicked: return "Hand-Picked"
        }
    }

    /// Same icons the "New Analysis" options sheet uses for each flow.
    var symbolName: String {
        switch self {
        case .standard: return "wand.and.stars"
        case .deep: return "sparkles"
        case .handPicked: return "photo.badge.plus"
        }
    }
}

extension AnalysisRecord {
    var kind: AnalysisKind {
        if deepVision != nil { return .handPicked }
        return (depth ?? .standard) == .deep ? .deep : .standard
    }
}
