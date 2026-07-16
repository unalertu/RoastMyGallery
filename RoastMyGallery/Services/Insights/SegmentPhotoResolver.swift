import Foundation

/// Decides which photos the results screen shows under each insight segment.
///
/// Extracted from `InsightView` so the deep-analysis captioning step can
/// target EXACTLY the photos the cards will display — the resolver is the
/// single source of truth for that mapping, used both when rendering and when
/// choosing which photos to upload for captions.
enum SegmentPhotoResolver {
    /// Candidate photos for each segment, in render order, de-duplicated
    /// across the whole narrative: once a photo is claimed by one beat it's
    /// pushed to the back of later beats' candidate lists, so two segments
    /// that share a category (e.g. two "screenshot" beats) surface different
    /// photos when the category indexed more than one. Each key holds up to
    /// two assets (see `StatsAggregator.photoIndex`), which covers the common
    /// case; if a category has only one photo, that lone photo is reused
    /// rather than showing nothing. Untagged/unindexed segments stay empty
    /// (text-only card).
    static func assetIDsPerSegment(
        segments: [Insight.Segment],
        photoIndex: [String: [String]]?
    ) -> [[String]] {
        var claimed: Set<String> = []
        return segments.map { segment in
            guard let category = segment.category,
                  let candidates = photoIndex?[category],
                  !candidates.isEmpty else { return [] }

            // Prefer photos no earlier beat has already shown.
            let fresh = candidates.filter { !claimed.contains($0) }
            let ordered = fresh + candidates.filter { claimed.contains($0) }

            // Claim the one the card will most likely display (its first
            // resolvable candidate) so the next beat avoids it.
            if let first = ordered.first { claimed.insert(first) }
            return ordered
        }
    }
}
