import Photos
import SwiftUI
import UIKit

enum SpikeError: LocalizedError {
    case noResource
    case noPermission

    var errorDescription: String? {
        switch self {
        case .noResource: return "Không đọc được PHAssetResource của asset"
        case .noPermission: return "Chưa được cấp quyền Photos"
        }
    }
}

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published var status: PHAuthorizationStatus

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    var statusLabel: String {
        switch status {
        case .authorized: return "authorized (full access)"
        case .limited: return "limited"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    // MARK: - Fetch helpers

    /// N ảnh mới nhất. includeHidden=true để fetch cả ảnh đã bị ẩn.
    func recentImages(limit: Int, includeHidden: Bool = false) -> [PHAsset] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if includeHidden { opts.includeHiddenAssets = true }
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        var out: [PHAsset] = []
        out.reserveCapacity(min(limit, result.count))
        result.enumerateObjects { asset, _, stop in
            out.append(asset)
            if out.count >= limit { stop.pointee = true }
        }
        return out
    }

    /// Fetch lại asset theo localIdentifier — luôn includeHiddenAssets
    /// vì fetch mặc định LOẠI TRỪ ảnh hidden (bẫy verify phổ biến).
    func asset(by localID: String) -> PHAsset? {
        let opts = PHFetchOptions()
        opts.includeHiddenAssets = true
        return PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: opts).firstObject
    }

    /// Tất cả ảnh đang hidden — để đối chiếu với Hidden album trong Photos app.
    func hiddenImages() -> [PHAsset] {
        let opts = PHFetchOptions()
        opts.includeHiddenAssets = true
        opts.predicate = NSPredicate(format: "isHidden == YES")
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        var out: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in out.append(asset) }
        return out
    }

    /// Albums (user albums) chứa asset — nền của tính năng "restore đúng album gốc".
    func albums(containing asset: PHAsset) -> [PHAssetCollection] {
        let result = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        var out: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in out.append(collection) }
        return out
    }

    /// Thumbnail để chạy model — network allowed cho iCloud-only assets.
    func thumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 256, height: 256)) async -> UIImage? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFill, options: opts
            ) { image, _ in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: image)
            }
        }
    }

    /// Data gốc (full quality) — dùng cho vault-copy trong S4.
    /// requestData trả về THEO CHUNK, phải cộng dồn.
    func originalData(for asset: PHAsset) async throws -> (Data, String) {
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            throw SpikeError.noResource
        }
        let filename = resource.originalFilename
        var buffer = Data()
        buffer.reserveCapacity(4 << 20)
        return (try await withCheckedThrowingContinuation { cont in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: nil,
                dataReceivedHandler: { chunk in buffer.append(chunk) },
                completionHandler: { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: buffer) }
                }
            )
        }), filename)
    }
}

extension UIImage {
    /// UIImage.cgImage có thể nil nếu backed bởi CIImage — fallback render.
    var cgImageFix: CGImage? {
        if let cg = cgImage { return cg }
        if let ci = ciImage {
            return CIContext().createCGImage(ci, from: ci.extent)
        }
        return nil
    }
}
