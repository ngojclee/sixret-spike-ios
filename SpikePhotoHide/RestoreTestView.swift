import CryptoKit
import Photos
import SwiftUI
import CoreLocation

/// S4 — Verify differentiator số 1: vault ảnh → xóa gốc → restore ĐÚNG ALBUM GỐC.
/// Flow: copy+encrypt vào sandbox → ghi mapping (albumIDs, metadata) →
/// deleteAssets → re-create → re-add albums → verify membership + metadata.

// MARK: - Mapping model + vault store (spike-grade, không phải production)

struct RestoreItem: Identifiable, Codable {
    var id: String { vaultFile }
    let originalID: String
    let vaultFile: String
    let albumIDs: [String]
    let albumNames: [String]
    let creationDate: Date?
    let lat: Double?
    let lon: Double?
    let filename: String
}

final class VaultStore {
    static let shared = VaultStore()

    /// Spike: key per-install trong memory. Production: Keychain/Secure Enclave.
    private let key = SymmetricKey(size: .bits256)

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var vaultDir: URL { docs.appendingPathComponent("Vault", isDirectory: true) }
    private var mapURL: URL { docs.appendingPathComponent("mapping.json") }

    init() {
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        // Không cho vault + mapping lên iCloud backup — nguyên tắc privacy.
        var vaultCopy = vaultDir, mapCopy = mapURL
        var skip = URLResourceValues(); skip.isExcludedFromBackup = true
        try? vaultCopy.setResourceValues(skip)
        if FileManager.default.fileExists(atPath: mapCopy.path) {
            try? mapCopy.setResourceValues(skip)
        }
    }

    func items() -> [RestoreItem] {
        guard let data = try? Data(contentsOf: mapURL) else { return [] }
        return (try? JSONDecoder().decode([RestoreItem].self, from: data)) ?? []
    }

    private func save(_ items: [RestoreItem]) {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: mapURL, options: .atomic)
            var copy = mapURL
            var skip = URLResourceValues(); skip.isExcludedFromBackup = true
            try? copy.setResourceValues(skip)
        }
    }

    /// Encrypt + ghi blob vào vault, thêm mapping.
    func vault(_ data: Data, item: RestoreItem) throws {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw SpikeError.noResource }
        try combined.write(to: vaultDir.appendingPathComponent(item.vaultFile))
        var all = items(); all.append(item); save(all)
    }

    func reveal(_ item: RestoreItem) throws -> Data {
        let blob = try Data(contentsOf: vaultDir.appendingPathComponent(item.vaultFile))
        let box = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(box, using: key)
    }

    func remove(_ item: RestoreItem) {
        try? FileManager.default.removeItem(at: vaultDir.appendingPathComponent(item.vaultFile))
        save(items().filter { $0.vaultFile != item.vaultFile })
    }
}

// MARK: - View

struct RestoreTestView: View {
    @EnvironmentObject var photos: PhotoLibrary
    @EnvironmentObject var log: LogStore

    @State private var busy = false
    @State private var candidates: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var vaultItems: [RestoreItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Restore đúng album gốc + giữ metadata", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.bold())
                    Text("Chuẩn bị: vài ảnh nằm trong ≥2 album khác nhau. Verify sau restore: album membership, creationDate, location, EXIF.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("1. Chọn ảnh (hiện 10 mới nhất + số album)") {
                    Button("Load ảnh") { loadCandidates() }
                    ForEach(candidates, id: \.localIdentifier) { asset in
                        let names = photos.albums(containing: asset).compactMap { $0.localizedTitle }
                        Button {
                            if selected.contains(asset.localIdentifier) {
                                selected.remove(asset.localIdentifier)
                            } else {
                                selected.insert(asset.localIdentifier)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(asset.localIdentifier)
                                      ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(asset.localIdentifier.suffix(10)).font(.caption.monospaced())
                                    Text(names.isEmpty ? "(không album)" : names.joined(separator: ", "))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button("2. Vault + Xóa gốc (\(selected.count))", role: .destructive) {
                        Task { await vaultAndDelete() }
                    }
                    .disabled(selected.isEmpty || busy)
                }

                Section("3. Trong vault (\(vaultItems.count))") {
                    ForEach(vaultItems) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.filename).font(.caption)
                                Text("albums: \(item.albumNames.joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { Task { await restore(item) } }
                                .disabled(busy)
                        }
                    }
                }
            }
            .navigationTitle("S4 · Restore")
            .overlay { if busy { ProgressView("Đang xử lý…") } }
            .onAppear { vaultItems = VaultStore.shared.items() }
        }
    }

    private func loadCandidates() {
        candidates = photos.recentImages(limit: 10)
        log.info("Load \(candidates.count) ảnh — chọn ảnh nằm trong ≥2 album để test tốt nhất")
    }

    private func vaultAndDelete() async {
        busy = true
        defer { busy = false }
        let targets = candidates.filter { selected.contains($0.localIdentifier) }

        for asset in targets {
            do {
                let (data, filename) = try await photos.originalData(for: asset)
                let albums = photos.albums(containing: asset)
                let item = RestoreItem(
                    originalID: asset.localIdentifier,
                    vaultFile: UUID().uuidString + ".enc",
                    albumIDs: albums.map { $0.localIdentifier },
                    albumNames: albums.compactMap { $0.localizedTitle },
                    creationDate: asset.creationDate,
                    lat: asset.location?.coordinate.latitude,
                    lon: asset.location?.coordinate.longitude,
                    filename: filename
                )
                try VaultStore.shared.vault(data, item: item)
                log.info("Vault \(filename) (\(data.count/1024)KB) — \(albums.count) album(s)")
            } catch {
                log.fail("Vault \(asset.localIdentifier.suffix(8))", error.localizedDescription)
            }
        }

        do {
            log.info("Gọi deleteAssets — quan sát dialog consent")
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(targets as NSArray)
            }
            log.pass("Đã xóa gốc \(targets.count) ảnh — check Recently Deleted")
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == "PHPhotosErrorDomain" && nsErr.code == 3072 {
                log.info("User cancel — vault vẫn giữ, nhưng gốc chưa xóa → restore sẽ tạo trùng. Bỏ item khỏi vault hoặc xóa lại.")
            } else {
                log.fail("deleteAssets", error.localizedDescription)
            }
        }
        vaultItems = VaultStore.shared.items()
        selected.removeAll()
    }

    private func restore(_ item: RestoreItem) async {
        busy = true
        defer { busy = false }

        guard let data = try? VaultStore.shared.reveal(item) else {
            log.fail("Reveal \(item.filename)", "giải mã lỗi")
            return
        }

        var newID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.originalFilename = item.filename
                req.addResource(with: .photo, data: data, options: opts)
                if let d = item.creationDate { req.creationDate = d }
                if let lat = item.lat, let lon = item.lon {
                    req.location = CLLocation(latitude: lat, longitude: lon)
                }
                newID = req.placeholderForCreatedAsset?.localIdentifier
                // Re-add vào đúng từng album gốc
                if let placeholder = req.placeholderForCreatedAsset {
                    for albumID in item.albumIDs {
                        if let coll = PHAssetCollection.fetchAssetCollections(
                            withLocalIdentifiers: [albumID], options: nil).firstObject,
                           let albumReq = PHAssetCollectionChangeRequest(for: coll) {
                            albumReq.addAssets([placeholder] as NSArray)
                        }
                    }
                }
            }
        } catch {
            log.fail("Restore create \(item.filename)", error.localizedDescription)
            return
        }

        // Verify: asset mới có về đúng album không + metadata giữ bao nhiêu
        guard let id = newID, let newAsset = photos.asset(by: id) else {
            log.fail("Restore verify \(item.filename)", "không fetch được asset mới")
            return
        }
        let restoredAlbums = Set(photos.albums(containing: newAsset).map { $0.localIdentifier })
        let expected = Set(item.albumIDs)
        let dateOK = newAsset.creationDate == item.creationDate
        let locOK = (newAsset.location != nil) == (item.lat != nil)

        if restoredAlbums == expected {
            log.pass("Restore \(item.filename): đúng \(restoredAlbums.count)/\(expected.count) album | date=\(dateOK) loc=\(locOK)")
        } else {
            log.fail("Restore albums \(item.filename)",
                     "expected \(expected), got \(restoredAlbums)")
        }
        VaultStore.shared.remove(item)
        vaultItems = VaultStore.shared.items()
    }
}
