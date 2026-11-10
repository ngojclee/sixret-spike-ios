import SwiftUI
import Photos

/// S3 — Verify G3: model NSFW on-device đủ nhanh + đủ chính xác.
/// Đo: ảnh/phút, ms/ảnh, số ảnh flagged @threshold, phân bố score.
/// PASS: ≥150 ảnh/phút trên iPhone tầm trung; recall/FPR đánh giá tay trên tập labeled.
struct BenchmarkView: View {
    @EnvironmentObject var photos: PhotoLibrary
    @EnvironmentObject var log: LogStore

    @State private var running = false
    @State private var sampleSize = 200
    @State private var progress = ""
    @State private var flaggedPreview: [(id: String, score: Double)] = []

    /// Bundled model nếu có, không thì skin-tone stub (chỉ smoke-test).
    private let scorer: NSFWScorer = BundledCoreMLScorer() ?? SkinToneScorer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("G3: model đủ tốt?", systemImage: "cpu")
                        .font(.subheadline.bold())
                    Text("Scorer đang dùng: **\(scorer.name)**")
                        .font(.footnote)
                    if scorer is SkinToneScorer {
                        Text("⚠️ Chưa có model thật trong bundle — kết quả chỉ để smoke-test pipeline, KHÔNG dùng đánh giá G3. Drop `NSFW.mlmodel` vào project rồi chạy lại.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section("Benchmark") {
                    Stepper("Số ảnh: \(sampleSize)", value: $sampleSize, in: 50...2000, step: 50)
                    Button("Chạy benchmark") { Task { await run() } }
                        .disabled(running)
                    if !progress.isEmpty {
                        Text(progress).font(.footnote.monospaced())
                    }
                }

                if !flaggedPreview.isEmpty {
                    Section("Flagged @0.7 (\(flaggedPreview.count)) — check tay để đo FPR") {
                        ForEach(flaggedPreview.sorted(by: { $0.score > $1.score }).prefix(30), id: \.id) { item in
                            HStack {
                                Text(item.id.suffix(12)).font(.caption2.monospaced())
                                Spacer()
                                Text(String(format: "%.2f", item.score)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("S3 · Model")
            .overlay { if running { ProgressView("Đang benchmark…") } }
        }
    }

    private func run() async {
        running = true
        flaggedPreview = []
        defer { running = false }

        let assets = photos.recentImages(limit: sampleSize, includeHidden: true)
        guard !assets.isEmpty else {
            log.info("Không có ảnh nào để benchmark")
            return
        }
        log.info("Bắt đầu benchmark scorer=\(scorer.name) trên \(assets.count) ảnh")

        var done = 0, flagged = 0, failed = 0
        var inferenceTimes: [Double] = []
        let start = Date()

        for asset in assets {
            guard let img = await photos.thumbnail(for: asset),
                  let cg = img.cgImageFix else {
                failed += 1
                continue
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            let s = (try? await scorer.score(cg)) ?? 0
            inferenceTimes.append(CFAbsoluteTimeGetCurrent() - t0)

            if s >= 0.7 {
                flagged += 1
                flaggedPreview.append((asset.localIdentifier, s))
            }
            done += 1
            if done % 50 == 0 {
                progress = "\(done)/\(assets.count) ảnh…"
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        let perMin = elapsed > 0 ? Double(done) / (elapsed / 60) : 0
        let avgMs = inferenceTimes.isEmpty ? 0
            : inferenceTimes.reduce(0, +) / Double(inferenceTimes.count) * 1000

        log.info("""
            KẾT QUẢ S3 — scorer=\(scorer.name)
              processed=\(done) failedThumb=\(failed)
              elapsed=\(String(format: "%.1f", elapsed))s → \(String(format: "%.0f", perMin)) ảnh/phút
              inference avg=\(String(format: "%.1f", avgMs))ms/ảnh
              flagged@0.7=\(flagged) (\(String(format: "%.1f", Double(flagged)/Double(max(done,1))*100))%)
              PASS tốc độ nếu ≥150 ảnh/phút → \(perMin >= 150 ? "PASS" : "CHƯA ĐẠT")
            """)
        progress = "Xong: \(Int(perMin)) ảnh/phút, \(flagged) flagged"
    }
}
