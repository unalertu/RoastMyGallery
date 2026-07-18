import SwiftUI

/// Results of one Deep Vision batch: the overall summary line on top, then
/// one card per commentary segment with the photo(s) it is about.
///
/// Photos resolve from two sources, in order:
/// 1. `previews` — the downscaled images kept in memory during the run, so the
///    fresh results screen never waits on PhotoKit.
/// 2. PHAsset lookup by asset ID (`SegmentThumbnailLoader`) — the History
///    path, where only IDs were persisted. A deleted photo (or a picker item
///    that never carried a real ID) degrades to a text-only card.
struct DeepVisionResultsView: View {
    let result: DeepVisionResult
    /// In-memory previews from the just-finished run, keyed by asset ID.
    /// Empty when rendering from History.
    var previews: [String: UIImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            summaryCard

            ForEach(Array(result.segments.enumerated()), id: \.element.id) { index, segment in
                DeepVisionSegmentCard(
                    segment: segment,
                    previews: previews,
                    fill: Theme.Colors.cardCycle[index % Theme.Colors.cardCycle.count].opacity(0.5)
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("The big picture", systemImage: "sparkles")
                .font(Theme.Typography.label)
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary.opacity(0.55))
                .textCase(.uppercase)

            Text(result.summary)
                .font(Theme.Typography.headline)
                .lineSpacing(Theme.Typography.bodyLineSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(fill: Theme.Colors.accentSoft)
    }
}

/// One commentary beat with the photo(s) it references. Text renders
/// immediately; thumbnails fade in as they resolve — no placeholders, no
/// broken states (same behavior as `InsightSegmentCard`).
private struct DeepVisionSegmentCard: View {
    let segment: DeepVisionResult.Segment
    let previews: [String: UIImage]
    let fill: Color

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var zoomedPhoto: ZoomablePhoto?

    private struct ResolvedImage: Identifiable {
        let id: String
        let image: UIImage
    }

    /// Up to three photos per card keeps the layout calm. Deduplicated first:
    /// the backend maps `photoIndexes` straight through and can reference the
    /// same photo twice, which would put a duplicate asset ID — and therefore a
    /// duplicate SwiftUI identity — into the `ForEach` below. That corrupts
    /// SwiftUI's identity map and crashes the app the moment the list animates
    /// from empty to populated (the History / cold-relaunch path, where
    /// thumbnails resolve asynchronously). Showing the same photo once per card
    /// is also just the correct behavior.
    private var displayAssetIDs: [String] {
        var seen = Set<String>()
        return Array(segment.assetIDs.filter { seen.insert($0).inserted }.prefix(3))
    }

    private var resolvedImages: [ResolvedImage] {
        displayAssetIDs.compactMap { id in
            (previews[id] ?? thumbnails[id]).map { ResolvedImage(id: id, image: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(segment.text)
                .font(Theme.Typography.body)
                .lineSpacing(Theme.Typography.bodyLineSpacing)

            let images = resolvedImages
            if !images.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(images) { item in
                        Image(uiImage: item.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: images.count == 1 ? 180 : 110)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
                            .contentShape(Rectangle())
                            .onTapGesture { zoomedPhoto = ZoomablePhoto(image: item.image, assetID: item.id) }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .photoZoom(photo: $zoomedPhoto)
        .task(id: segment.id) {
            // History path: resolve whatever the in-memory previews don't cover.
            for id in displayAssetIDs where previews[id] == nil && thumbnails[id] == nil {
                guard let image = await SegmentThumbnailLoader.thumbnail(for: [id]) else { continue }
                withAnimation(Theme.motion) { thumbnails[id] = image }
            }
        }
    }
}

/// History detail for a persisted Deep Vision entry (`record.deepVision`
/// non-nil): persona/date header + the shared results list.
struct DeepVisionRecordView: View {
    let record: AnalysisRecord

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    if let result = record.deepVision {
                        DeepVisionResultsView(result: result)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                PersonaChip(persona: record.persona)
                Spacer()
                Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text(record.insight.headline)
                .font(Theme.Typography.display)
                .padding(.top, Theme.Spacing.s)

            Label("Deep Vision — photo-by-photo commentary", systemImage: "sparkles")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.top, Theme.Spacing.l)
    }
}
