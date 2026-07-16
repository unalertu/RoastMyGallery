import SwiftUI

// MARK: - Builder

/// Turns an `AnalysisRecord` into fully-resolved `FullStoryPanel`s: picks the
/// same per-segment photos the results screen shows (`SegmentPhotoResolver` is
/// the single source of truth for that mapping), loads them as thumbnails, and
/// paginates beats into 9:16 pages.
///
/// Async because of the photo loads — everything is resolved BEFORE rendering,
/// since `ImageRenderer` snapshots synchronously and can't await inside the
/// view tree. Photo loads are best-effort: a failed load just means a
/// text-only page, mirroring `InsightSegmentCard`.
enum FullStoryBuilder {
    /// Beat pages beyond this are dropped (the closing panel notes how many
    /// beats were left out). Keeps deep stories from producing an unwieldy
    /// pile of panels and bounds render work: with cover + closing the set
    /// never exceeds 10 images.
    static let maxBeatPanels = 8

    /// Rendered photo area is ~280pt wide @3x = 840px; request a bit above so
    /// the share image stays sharp.
    private static let thumbnailSide: CGFloat = 900

    static func panels(for record: AnalysisRecord) async -> [FullStoryPanel] {
        let segments = storySegments(for: record)

        let assetIDsPerSegment = SegmentPhotoResolver.assetIDsPerSegment(
            segments: segments,
            photoIndex: record.categoryPhotoIndex
        )

        // Resolve thumbnails concurrently, keyed by segment index so order
        // survives the task group's completion order.
        let resolved: [Int: SegmentThumbnailLoader.Resolved] = await withTaskGroup(
            of: (Int, SegmentThumbnailLoader.Resolved?).self
        ) { group in
            for (index, assetIDs) in assetIDsPerSegment.enumerated() where !assetIDs.isEmpty {
                group.addTask {
                    (index, await SegmentThumbnailLoader.resolve(assetIDs, side: thumbnailSide))
                }
            }
            var out: [Int: SegmentThumbnailLoader.Resolved] = [:]
            for await (index, result) in group {
                if let result { out[index] = result }
            }
            return out
        }

        let beats: [FullStoryPanel.ResolvedBeat] = segments.enumerated().map { index, segment in
            let match = resolved[index]
            return FullStoryPanel.ResolvedBeat(
                text: segment.text,
                photo: match?.image,
                caption: match.flatMap { record.photoCaptions?[$0.assetID] }
            )
        }

        // Page assembly, narrative order preserved: a beat with a photo owns
        // its page; consecutive text-only beats pair up two per page.
        var pages: [[FullStoryPanel.ResolvedBeat]] = []
        var pendingTextOnly: [FullStoryPanel.ResolvedBeat] = []
        for beat in beats {
            if beat.photo != nil {
                if !pendingTextOnly.isEmpty {
                    pages.append(pendingTextOnly)
                    pendingTextOnly = []
                }
                pages.append([beat])
            } else {
                pendingTextOnly.append(beat)
                if pendingTextOnly.count == 2 {
                    pages.append(pendingTextOnly)
                    pendingTextOnly = []
                }
            }
        }
        if !pendingTextOnly.isEmpty {
            pages.append(pendingTextOnly)
        }

        var hiddenBeatCount = 0
        if pages.count > maxBeatPanels {
            hiddenBeatCount = pages[maxBeatPanels...].reduce(0) { $0 + $1.count }
            pages = Array(pages.prefix(maxBeatPanels))
        }

        return [.cover] + pages.map { .beats($0) } + [.closing(hiddenBeatCount: hiddenBeatCount)]
    }

    /// Segments when the insight has them; otherwise (older records, legacy
    /// backend responses) the body's paragraphs become untagged pseudo-beats
    /// so the Full Story format still covers the whole narrative.
    private static func storySegments(for record: AnalysisRecord) -> [Insight.Segment] {
        if let segments = record.insight.segments, !segments.isEmpty {
            return segments
        }
        return record.insight.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Insight.Segment(text: $0, category: nil) }
    }
}

// MARK: - Renderer

/// Renders the resolved Full Story panels at 1080×1920 each.
///
/// Deliberately NOT a `ShareCardRendering` conformer: that protocol's shape is
/// one `(insight, stats) → UIImage`, while the Full Story needs the whole
/// record (photo index, captions, depth) and produces a set of images. The two
/// existing single-card renderers are untouched.
@MainActor
struct FullStoryRenderer {
    func render(record: AnalysisRecord, panels: [FullStoryPanel]) async throws -> [UIImage] {
        let variant = AltCardVariant.seeded(by: record.insight.id)
        var images: [UIImage] = []
        images.reserveCapacity(panels.count)

        for (index, panel) in panels.enumerated() {
            let view = FullStoryPanelView(
                record: record,
                panel: panel,
                index: index + 1,
                total: panels.count,
                variant: variant
            )
            .frame(width: 360, height: 640)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 3 // 1080×1920 per panel

            guard let image = renderer.uiImage else {
                throw ShareCardRenderer.RenderError.renderFailed
            }
            images.append(image)

            // Let the run loop breathe between panels so the results screen's
            // "preparing" state stays responsive on long deep stories.
            await Task.yield()
        }
        return images
    }
}
