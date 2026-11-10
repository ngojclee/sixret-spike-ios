import SwiftUI
import Photos

/// S2 — Verify G2: flow xóa batch có chấp nhận được ở scale không.
/// Đo: số dialog hệ thống, số lần tap, hành vi Recently Deleted, iCloud sync.
/// ⚠️ XÓA THẬT — chỉ chạy trên máy test / ảnh test.
struct DeleteTestView: View {
    @EnvironmentObject var photos: PhotoLibrary
    @EnvironmentObject var log: LogStore
    @State private var busy = false
    @State private var batchSize = 5

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("G2: delete batch + consent UX", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.bold())
                    Text("XÓA THẬT. Dùng ảnh test. Ghi vào report: số dialog xuất hiện, số lần tap để xóa xong batch, nội dung dialog.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Test") {
                    Stepper("Batch size: \(batchSize)", value: $batchSize, in: 1...50)
                    Button("Xóa batch \(batchSize) ảnh mới nhất", role: .destructive) {
                        Task { await runDelete() }
                    }
                    Button("Check: đọc số ảnh trong Recently Deleted") {
                        checkRecentlyDeleted()
                    }
                }
                .disabled(busy)

                Section("Ghi nhớ verify tay") {
                    Text("• Vào Photos → Recently Deleted: ảnh có nằm đó không, có cách nào xóa hẳn từ app không (dự đoán: không)")
                    Text("• Nếu bật iCloud Photos: check device thứ 2 xem ảnh có biến mất luôn không → \"xóa khỏi iCloud\" là feature bán được")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            .navigationTitle("S2 · Delete UX")
            .overlay { if busy { ProgressView("Đang xóa…") } }
        }
    }

    private func runDelete() async {
        busy = true
        defer { busy = false }
        let assets = photos.recentImages(limit: batchSize)
        guard !assets.isEmpty else {
            log.info("Không còn ảnh nào để xóa")
            return
        }
        log.info("Gọi deleteAssets trên batch \(assets.count) — QUAN SÁT dialog + đếm số lần tap")
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            log.pass("deleteAssets batch \(assets.count) — hệ thống đã xóa, check Recently Deleted")
        } catch {
            // User cancel cũng đi vào đây — đó là data: cancel = consent dialog hoạt động
            let nsErr = error as NSError
            if nsErr.domain == "PHPhotosErrorDomain" && nsErr.code == 3072 {
                log.info("User CANCEL dialog — consent flow hoạt động đúng (đây là behavior mong muốn)")
            } else {
                log.fail("deleteAssets", "\(nsErr.domain) \(nsErr.code): \(error.localizedDescription)")
            }
        }
    }

    /// Recently Deleted = smart album type 100000002? Không — dùng fetchAssetCollections
    /// với subtype .smartAlbumRecentlyDeleted (iOS 16+ nằm sau Face ID).
    private func checkRecentlyDeleted() {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumRecentlyDeleted, options: nil)
        if let rd = result.firstObject {
            let count = PHAsset.fetchAssets(in: rd, options: nil).count
            log.info("Recently Deleted đang có \(count) items")
        } else {
            log.info("Không fetch được Recently Deleted collection")
        }
    }
}
