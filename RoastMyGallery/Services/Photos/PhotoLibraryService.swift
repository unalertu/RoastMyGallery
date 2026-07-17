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
    /// The user's regular (non-smart) albums that contain at least one photo,
    /// for the album-scoped analysis mode.
    func fetchUserAlbums() -> [PhotoLibraryService.AlbumInfo]
}

struct PhotoLibraryService: PhotoLibraryProviding {
    struct AlbumInfo: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let photoCount: Int
    }

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
        if let end = scope.endDate {
            // `endDate` is inclusive to whole-second granularity (the month
            // picker stores "23:59:59 of the last day"). Compare with `<`
            // against the next whole second so assets whose creationDate has
            // a sub-second component inside that final second (23:59:59.4)
            // aren't silently excluded from the range.
            predicates.append(NSPredicate(format: "creationDate < %@", end.addingTimeInterval(1) as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        if let albumID = scope.albumIdentifier {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumID], options: nil
            )
            guard let album = collections.firstObject else {
                // Album was deleted/renamed since it was picked — fetch
                // nothing rather than silently falling back to the library.
                let emptyOptions = PHFetchOptions()
                emptyOptions.predicate = NSPredicate(value: false)
                return PHAsset.fetchAssets(with: emptyOptions)
            }
            return PHAsset.fetchAssets(in: album, options: options)
        }

        return PHAsset.fetchAssets(with: options)
    }

    func fetchUserAlbums() -> [AlbumInfo] {
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        var albums: [AlbumInfo] = []
        var seenIDs = Set<String>()

        // 1. User albums of every kind — regular, synced, imported, and
        //    iCloud shared. `.any` (vs `.albumRegular`) is what makes shared
        //    and synced albums show up in the picker instead of silently
        //    dropping out.
        let userCollections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userCollections.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: imageOptions).count
            guard count > 0 else { return }
            let id = collection.localIdentifier
            guard seenIDs.insert(id).inserted else { return }
            albums.append(AlbumInfo(
                id: id,
                title: collection.localizedTitle ?? "Untitled Album",
                photoCount: count
            ))
        }

        // 2. Smart albums (Favorites, Selfies, Screenshots, Recents, etc.)
        let smartSubtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumFavorites,
            .smartAlbumSelfPortraits,
            .smartAlbumScreenshots,
            .smartAlbumPanoramas,
            .smartAlbumLivePhotos,
            .smartAlbumDepthEffect,
            .smartAlbumBursts,
            .smartAlbumRecentlyAdded
        ]
        for subtype in smartSubtypes {
            let smartCollections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil
            )
            smartCollections.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: imageOptions).count
                guard count > 0 else { return }
                let id = collection.localIdentifier
                guard seenIDs.insert(id).inserted else { return }
                albums.append(AlbumInfo(
                    id: id,
                    title: collection.localizedTitle ?? "Smart Album",
                    photoCount: count
                ))
            }
        }

        return albums.sorted { $0.photoCount > $1.photoCount }
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
