import Foundation
import SwiftUI

/// Log đơn giản hiển thị trong app — mọi kết quả test đều đổ vào đây
/// để copy ra làm bằng chứng cho report S5.
@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var lines: [String] = []

    func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lines.append("[\(stamp)] \(message)")
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }

    func pass(_ name: String) { log("✅ PASS — \(name)") }
    func fail(_ name: String, _ why: String) { log("❌ FAIL — \(name): \(why)") }
    func info(_ msg: String) { log("ℹ️ \(msg)") }

    func clear() { lines.removeAll() }

    var reportText: String { lines.joined(separator: "\n") }
}
