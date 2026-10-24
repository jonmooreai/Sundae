import Foundation
import Photos
import UIKit

/// Read access to the camera roll for the "this week" default filter and the
/// "add Thursday's photos" prompt. PhotosPicker needs no permission, so this is only
/// requested when the user asks for the filter, and the picker keeps working without it.
@MainActor
@Observable
final class PhotoLibrary {
    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var assets: [PHAsset] = []
    private let manager = PHCachingImageManager()

    var isAuthorized: Bool { status == .authorized || status == .limited }
    var canAsk: Bool { status == .notDetermined }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Images taken in [start, end), oldest first so the default order is chronological.
    func loadAssets(from start: Date, to end: Date) {
        guard isAuthorized else {
            assets = []
            return
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let scale = UIScreen.main.scale
        let target = CGSize(width: side * scale, height: side * scale)
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Full-resolution bytes for one asset, handed straight to `PhotoProcessor`.
    func imageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
