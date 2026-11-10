import CoreImage
import CoreML
import Vision

/// Abstraction cho model NSFW — S3 benchmark qua protocol này
/// để đổi model không đổi pipeline.
protocol NSFWScorer {
    var name: String { get }
    /// 0.0–1.0, càng cao càng có khả năng nhạy cảm.
    func score(_ image: CGImage) async throws -> Double
}

// MARK: - Bundled CoreML scorer

/// Load model NSFW từ bundle. Hỗ trợ .mlmodelc (đã compile), .mlmodel
/// (compile lúc runtime), .mlpackage.
///
/// CÁCH DÙNG: drop file model vào target, đặt tên `NSFW` (vd: NSFW.mlmodel).
/// Gợi ý model: open_nsfw CoreML port, hoặc MobileNetV2 NSFW classifier.
/// Mapping label: model nào có label chứa nsfw/porn/explicit/sexy → dùng
/// confidence đó; model 2-class "safe/sfw" → trả về 1 - safeConfidence.
final class BundledCoreMLScorer: NSFWScorer {
    let name: String
    private let vnModel: VNCoreMLModel

    init?() {
        guard let model = Self.loadBundledModel(),
              let vn = try? VNCoreMLModel(for: model) else { return nil }
        vnModel = vn
        name = "BundledCoreML"
    }

    private static func loadBundledModel() -> MLModel? {
        if let url = Bundle.main.url(forResource: "NSFW", withExtension: "mlmodelc"),
           let m = try? MLModel(contentsOf: url) { return m }
        if let url = Bundle.main.url(forResource: "NSFW", withExtension: "mlmodel"),
           let compiled = try? MLModel.compileModel(at: url),
           let m = try? MLModel(contentsOf: compiled) { return m }
        if let url = Bundle.main.url(forResource: "NSFW", withExtension: "mlpackage"),
           let m = try? MLModel(contentsOf: url) { return m }
        return nil
    }

    func score(_ image: CGImage) async throws -> Double {
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let results = request.results as? [VNClassificationObservation], !results.isEmpty else {
            return 0
        }
        // 1. Label "nhạy cảm" trực tiếp
        let sensitiveKeys = ["nsfw", "porn", "explicit", "sexy", "nude", "hentai"]
        if let hit = results.first(where: {
            let id = $0.identifier.lowercased()
            return sensitiveKeys.contains(where: id.contains)
        }) {
            return Double(hit.confidence)
        }
        // 2. Model 2-class kiểu safe/sfw → đảo
        if let safe = results.first(where: {
            let id = $0.identifier.lowercased()
            return id.contains("sfw") || id.contains("safe") || id.contains("neutral")
        }) {
            return 1.0 - Double(safe.confidence)
        }
        // 3. Không map được → trả 0 và để log cảnh báo ở caller
        return 0
    }
}

// MARK: - Skin-tone stub (KHÔNG phải model thật)

/// Đếm tỉ lệ pixel "màu da" theo rule đơn giản (Kovac-style).
/// Chỉ để smoke-test pipeline khi chưa có model — KHÔNG dùng làm bằng chứng G3.
final class SkinToneScorer: NSFWScorer {
    let name = "SkinToneStub(KHÔNG-PHẢI-MODEL)"

    func score(_ image: CGImage) async throws -> Double {
        let w = 64, h = 64
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var skin = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            // Rule: da sáng/tb — r > g > b, r cao, chênh lệch đủ lớn
            if r > 95, g > 40, b > 20, r > g, r > b,
               (r - min(g, b)) > 15, abs(r - g) > 15 {
                skin += 1
            }
        }
        return Double(skin) / Double(w * h)
    }
}
