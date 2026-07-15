import Photos
import SwiftUI

/// One insight segment: the narrative beat, plus — when the segment is tagged
/// with a category we indexed during the scan — a representative photo from
/// the user's own library underneath it.
///
/// The photo lookup is entirely on-device (PHImageManager over persisted asset
/// IDs); nothing here talks to the network beyond iCloud photo loading, and it
/// never blocks the text: the card renders immediately and the thumbnail fades
/// in when (and only if) it resolves. No match / failed load → text-only card,
/// no placeholder or broken state.
struct InsightSegmentCard: View {
    let segment: Insight.Segment
    /// Candidate asset local identifiers for this segment's category,
    /// preferred order first. Empty when the category has no indexed photo.
    let assetIDs: [String]

    @State private var thumbnail: UIImage?
    @State private var zoomedPhoto: ZoomablePhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(segment.text)
                .font(Theme.Typography.body)
                .lineSpacing(Theme.Typography.bodyLineSpacing)

            if let thumbnail {
                let isLandscape = thumbnail.size.width > thumbnail.size.height
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: isLandscape ? .fit : .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: isLandscape ? nil : 220, alignment: .center)
                    .frame(maxHeight: isLandscape ? 220 : 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
                    .contentShape(Rectangle())
                    .transition(.opacity)
                    .onTapGesture { zoomedPhoto = ZoomablePhoto(image: thumbnail, assetID: assetIDs.first) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .photoZoom(photo: $zoomedPhoto)
        .task(id: assetIDs) {
            guard thumbnail == nil, !assetIDs.isEmpty else { return }
            guard let image = await SegmentThumbnailLoader.thumbnail(for: assetIDs) else { return }
            withAnimation(Theme.motion) { thumbnail = image }
        }
    }
}

/// Resolves persisted asset local identifiers into a small thumbnail.
/// Tries candidates in order so a deleted photo just falls through to the
/// next one (or to no photo at all).
enum SegmentThumbnailLoader {
    static func thumbnail(for assetIDs: [String], side: CGFloat = 400) async -> UIImage? {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard fetched.count > 0 else { return nil }

        // Fetch results don't preserve input order; restore our preference.
        var byID: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        for id in assetIDs {
            guard let asset = byID[id] else { continue }
            if let image = await requestImage(for: asset, side: side) { return image }
        }
        return nil
    }

    private static func requestImage(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        // Synchronous request on a background task: exactly one callback,
        // no degraded intermediates, no continuation double-resume hazards.
        let assetID = asset.localIdentifier
        return await Task.detached(priority: .userInitiated) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                .firstObject else { return nil }

            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            // Photo originals may live in iCloud; a thumbnail-sized fetch is fine.
            options.isNetworkAccessAllowed = true

            var result: UIImage?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                result = image
            }
            return result
        }.value
    }
}
