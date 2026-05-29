// Verification harness (test-only, NOT part of the app).
// Prints the zh-Hans -> target support matrix (AC-VER-02) and, for installed pairs,
// performs a real system translation with latency samples (AC-VER-03/05, AC-TR-06).
//
// Uses TranslationSession(installedSource:target:) — a macOS 26 convenience init — to
// translate headlessly without a SwiftUI view. The shipping app instead drives
// translation through the .translationTask modifier (min target macOS 15).
import Foundation
import Translation

let targets: [(String, String)] = [
    ("en", "英语"), ("ja", "日语"), ("pt", "葡萄牙语"), ("es", "西班牙语"),
    ("ko", "韩语"), ("fr", "法语"), ("de", "德语")
]
let source = Locale.Language(identifier: "zh-Hans")
let samples = ["你好，最近怎么样？", "请问这个订单什么时候发货？", "感谢你的耐心，我们会尽快处理。"]

func statusName(_ s: LanguageAvailability.Status) -> String {
    switch s {
    case .installed: return "已就绪 installed"
    case .supported: return "需准备 supported"
    case .unsupported: return "暂不支持 unsupported"
    @unknown default: return "unknown"
    }
}

@main
struct Verify {
    static func main() async {
        let availability = LanguageAvailability()
        print("==== zh-Hans → target 支持矩阵 (AC-VER-02) ====")
        var installed: [(String, String)] = []
        for (code, name) in targets {
            let st = await availability.status(from: source, to: Locale.Language(identifier: code))
            print(String(format: "  %-4@ %@  →  %@", code as NSString, name as NSString, statusName(st) as NSString))
            if st == .installed { installed.append((code, name)) }
        }

        guard #available(macOS 26.0, *) else {
            print("\n(系统 < 26，跳过无头翻译实测；应用本身仍按 macOS 15 的 .translationTask 路径工作)")
            return
        }

        print("\n==== 已安装语言对真实翻译 + 延迟 (AC-VER-03 / AC-TR-06 / AC-PERF-02) ====")
        if installed.isEmpty {
            print("  当前无已安装语言对。请在系统设置→翻译/语言中下载至少一个语言包后重测。")
        }
        let runs = 20
        for (code, name) in installed {
            let session = TranslationSession(installedSource: source,
                                             target: Locale.Language(identifier: code))
            // 1 warmup (excluded) + `runs` measured, all ≤100 字 (AC-TR-06 condition).
            _ = try? await session.translate(samples[0])
            var latencies: [Double] = []
            var firstOut = ""
            for i in 0..<runs {
                let text = samples[i % samples.count]
                let t0 = Date()
                do {
                    let resp = try await session.translate(text)
                    latencies.append(Date().timeIntervalSince(t0) * 1000)
                    if i == 0 { firstOut = resp.targetText }
                } catch {
                    print("  [\(code)] 翻译失败: \(error)")
                }
            }
            guard !latencies.isEmpty else { continue }
            let sorted = latencies.sorted()
            let p50 = sorted[Int(Double(sorted.count) * 0.50)]
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            print(String(format: "  [%@ %@] 示例「你好，最近怎么样？」→「%@」", code as NSString, name as NSString, firstOut as NSString))
            print(String(format: "         n=%d  P50=%.0fms  P95=%.0fms  (阈值 P95≤500ms %@)",
                         runs, p50, p95, (p95 <= 500 ? "✓达标" : "✗超阈") as NSString))
        }
        print("\n完成。")
    }
}
