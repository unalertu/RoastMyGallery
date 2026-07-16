import Foundation

/// Structured, privacy-safe metadata extracted from a single photo,
/// entirely on-device. This is the intermediate unit that `StatsAggregator`
/// folds into a `PhotoStats` object. It never contains pixel data.
struct PhotoObservation: Sendable, Equatable {
    /// PhotoKit local identifier — stays on device, never serialized to the backend.
    let assetID: String

    let creationDate: Date?

    /// Coarse location, already rounded to ~city-level precision so exact
    /// coordinates never leave the analyzer. `nil` if the photo has no GPS data.
    let coarseLocation: CoarseLocation?

    let isSelfie: Bool
    let isScreenshot: Bool
    let isFavorite: Bool

    /// Number of faces detected by Vision (VNDetectFaceRectanglesRequest).
    let faceCount: Int

    /// Top scene/object classification labels above the confidence threshold
    /// (VNClassifyImageRequest) with their Vision confidence, e.g.
    /// [("food", 0.82), ("plate", 0.55)]. Confidence lets `photoIndex` rank the
    /// representative photo for each category by match strength rather than
    /// recency (see StatsAggregator).
    let categories: [ScoredCategory]

    /// Detected animal labels (VNRecognizeAnimalsRequest), e.g. ["cat"].
    let animals: [String]

    /// One scene/object label with its Vision classification confidence (0…1).
    struct ScoredCategory: Sendable, Equatable {
        let identifier: String
        let confidence: Float
    }
}

/// A deliberately low-precision location bucket (~11 km grid at the equator)
/// so aggregated stats can say "mostly around one area" without ever holding
/// exact coordinates.
struct CoarseLocation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(roundingLatitude latitude: Double, longitude: Double) {
        // One decimal place ≈ 11 km — coarse enough to be non-identifying
        // at the aggregate level, fine enough for "top areas" clustering.
        self.latitude = (latitude * 10).rounded() / 10
        self.longitude = (longitude * 10).rounded() / 10
    }
}
