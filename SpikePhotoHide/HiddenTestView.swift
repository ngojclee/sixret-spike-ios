import SwiftUI
import Photos

/// S1 — Verify G1: app bên thứ ba set được `PHAssetChangeRequest.isHidden`.
/// PASS: set/unset được, không cần confirm per-asset.
/// FAIL candidates: lỗi permission, silent-ignore (set xong flag vẫn false),
/// chỉ writable trên ảnh app tự tạo.
struct HiddenTestView: View {
    @EnvironmentObject var photos: PhotoLibrary
    @EnvironmentObject var log: LogStore
    @State private var busy = false
    @State private var hiddenIDs: [String] =
        UserDefaults.standard.stringArray(forKey: "spikeHiddenIDs") ?? []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("G1: isHidden writable bởi 3rd-party?", systemImage: "questionmark.circle")
                        .font(.subheadline.bold())
                    Text("Sau mỗi lần set: mở Photos app kiểm tra Hidden album. Ghi vào report: có dialog confirm không, ảnh có vào Hidden không.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Các bước test") {
                    Button("1. Set isHidden = true (3 ảnh mới nhất)") {
                        Task { await setHidden(onNewest: true) }
                    }
                    Button("2. Fetch lại danh sách hidden") {
                        verifyHiddenFetch()
                    }
                    Button("3. Unhide tất cả ảnh test đã ẩn") {
                        Task { await unhideAll() }
                    }
                    .disabled(hiddenIDs.isEmpty)
                }
                .disabled(busy)

                if !hiddenIDs.isEmpty {
                    Section("Asset IDs đã ẩn bởi test (\(hiddenIDs.count))") {
                        ForEach(hiddenIDs, id: \.self) { id in
                            Text(id).font(.caption2.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("S1 · isHidden")
            .overlay { if busy { ProgressView("Đang xử lý…") } }
        }
    }

    // MARK: - Test steps

    private func setHidden(onNewest: Bool) async {
        busy = true
        defer { busy = false }
        let assets = photos.recentImages(limit: 3)
        log.info("Bắt đầu set isHidden=true trên \(assets.count) ảnh — QUAN SÁT dialog hệ thống (nếu có)")

        for asset in assets {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest(for: asset).isHidden = true
                }
                let nowHidden = photos.asset(by: asset.localIdentifier)?.isHidden
                if nowHidden == true {
                    log.pass("isHidden=true trên \(shortID(asset)) — mở Photos app check Hidden album")
                    hiddenIDs.append(asset.localIdentifier)
                } else {
                    log.fail("isHidden trên \(shortID(asset))",
                             "không lỗi nhưng flag vẫn \(String(describing: nowHidden)) → có thể bị silent-ignore")
                }
            } catch {
                log.fail("isHidden trên \(shortID(asset))", error.localizedDescription)
            }
        }
        UserDefaults.standard.set(hiddenIDs, forKey: "spikeHiddenIDs")
    }

    private func verifyHiddenFetch() {
        let hidden = photos.hiddenImages()
        log.info("Fetch được \(hidden.count) ảnh hidden qua includeHiddenAssets — đối chiếu số này với Hidden album trong Photos")
    }

    private func unhideAll() async {
        busy = true
        defer { busy = false }
        for id in hiddenIDs {
            guard let asset = photos.asset(by: id) else { continue }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest(for: asset).isHidden = false
                }
                if photos.asset(by: id)?.isHidden == false {
                    log.pass("Unhide \(id.suffix(8)) — ảnh về đúng album cũ?")
                } else {
                    log.fail("Unhide \(id.suffix(8))", "flag không đổi")
                }
            } catch {
                log.fail("Unhide \(id.suffix(8))", error.localizedDescription)
            }
        }
        hiddenIDs.removeAll()
        UserDefaults.standard.set(hiddenIDs, forKey: "spikeHiddenIDs")
    }

    private func shortID(_ asset: PHAsset) -> String {
        String(asset.localIdentifier.suffix(8))
    }
}
