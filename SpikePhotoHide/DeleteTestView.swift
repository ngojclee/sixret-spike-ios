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

    /// Không có API đọc "Recently Deleted": nó là smart album hệ thống, khoá sau
    /// Face ID và không expose qua PHAssetCollectionSubtype. Kiểm tra bằng mắt
    /// trong app Photos — đó cũng là bằng chứng cần ghi vào report.
    private func checkRecentlyDeleted() {
        log.info("Recently Deleted: mở Photos → Albums → Recently Deleted (Face ID) để đếm bằng mắt")
    }
}
