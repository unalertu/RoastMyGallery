import Foundation
import Photos

/// Thin wrapper around PhotoKit authorization + asset enumeration so the rest
/// of the app never touches `PHPhotoLibrary` directly.
protocol PhotoLibraryProviding: Sendable {
    func currentAuthorizationStatus() -> PHAuthorizationStatus
    func requestAuthorization() async -> PHAuthorizationStatus
    /// All image assets within the scope, newest first.
    func fetchAssets(in scope: AnalysisScope) -> PHFetchResult<PHAsset>
    /// Local identifiers of assets in the "Selfies" smart album, used to tag
    /// observations as selfies without any ML guesswork.
    func selfieAssetIDs() -> Set<String>
}

struct PhotoLibraryService: PhotoLibraryProviding {
    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func fetchAssets(in scope: AnalysisScope) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates: [NSPredicate] = [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        ]
        if let start = scope.startDate {
            predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return PHAsset.fetchAssets(with: options)
    }

    func selfieAssetIDs() -> Set<String> {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil
        )
        var ids = Set<String>()
        collections.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }
}
