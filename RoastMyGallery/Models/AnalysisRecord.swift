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
}
