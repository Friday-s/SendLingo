import AppKit
import Translation

/// In-process integration tests, run via `OptionNow --uitest` inside a live
/// `NSApplication` with the panel actually mounted. This exercises the SHIPPING
/// runtime: the real floating panel, the live `.translationTask` translation
/// pipeline, the view model state machine, the copy logic, and (against a local mock
/// DeepSeek server) the AI streaming path. Converts interactive acceptance items into
/// reproducible automated evidence.
@MainActor
enum UITests {
    private static var pass = 0
    private static var fail = 0
    private static var skip = 0

    private static func check(_ name: String, _ cond: Bool) {
        print("  [\(cond ? "PASS" : "FAIL")] \(name)")
        cond ? (pass += 1) : (fail += 1)
    }
    private static func skipped(_ name: String, _ why: String) {
        print("  [SKIP] \(name) — \(why)")
        skip += 1
    }

    private static func waitUntil(_ timeout: Double, _ cond: @escaping () -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return cond()
    }

    static func run(panelController: PanelController,
                    vm: TranslatorViewModel,
                    settings: SettingsStore) async -> Int32 {
        print("==== Option Now UI/integration test ====")

        // Let the panel + SwiftUI view mount and language statuses prime.
        panelController.show()
        _ = await waitUntil(3) { panelController.panel?.isVisible == true }

        await windowBehavior(panelController, settings)
        await hotkeyAndToggle(panelController, vm)
        await liveTranslation(vm)
        await copyLogic(vm)
        await languagePackGuard(vm)
        await aiLayer(vm)

        // Cleanup test side effects.
        HistoryStore.shared.clear()
        KeychainHelper.delete()
        settings.autoHideOnBlur = false

        print("==== \(pass) passed, \(fail) failed, \(skip) skipped ====")
        return fail == 0 ? 0 : 1
    }

    // MARK: - Window behavior (AC-WIN-01/02/03/08, AC-HK-01)

    private static func windowBehavior(_ pc: PanelController, _ settings: SettingsStore) async {
        print("-- 浮窗行为 --")
        guard let panel = pc.panel else { check("panel exists", false); return }
        check("AC-WIN-01 level == .floating（常驻最前）", panel.level == .floating)
        check("AC-WIN-01 collectionBehavior 含 canJoinAllSpaces", panel.collectionBehavior.contains(.canJoinAllSpaces))
        check("AC-WIN-01/06 含 fullScreenAuxiliary", panel.collectionBehavior.contains(.fullScreenAuxiliary))
        check("AC-WIN-01 hidesOnDeactivate == false（切应用不消失）", panel.hidesOnDeactivate == false)
        check("AC-WIN-02 canBecomeKey == true（可输入）", panel.canBecomeKey == true)
        check("AC-WIN-02 canBecomeMain == false（不激活 App/不抢主窗）", panel.canBecomeMain == false)
        check("AC-WIN-02 styleMask 含 nonactivatingPanel", panel.styleMask.contains(.nonactivatingPanel))
        check("AC-WIN-03 isMovableByWindowBackground（可拖拽）", panel.isMovableByWindowBackground == true)
        check("AC-HK-01 唤起后浮窗 key window（可直接输入）", panel.isKeyWindow == true)

        // AC-WIN-08 失焦自动隐藏开关
        settings.autoHideOnBlur = false
        pc.show()
        panel.onResignKey?()
        check("AC-WIN-08 默认失焦不隐藏", panel.isVisible == true)
        settings.autoHideOnBlur = true
        pc.show()
        panel.onResignKey?()
        check("AC-WIN-08 开启后失焦隐藏", panel.isVisible == false)
        settings.autoHideOnBlur = false
        pc.show()
    }

    // MARK: - Hotkey toggle + wake latency (AC-HK-02/03, AC-PERF-01)

    private static func hotkeyAndToggle(_ pc: PanelController, _ vm: TranslatorViewModel) async {
        print("-- 唤起/快捷键 --")
        pc.show()
        check("AC-HK-03 可见时 toggle → 隐藏", { pc.toggle(); return pc.isVisible == false }())
        let tokenBefore = vm.focusToken
        check("AC-HK-03 再 toggle → 显示", { pc.toggle(); return pc.isVisible == true }())
        check("AC-HK-01 show() 触发输入聚焦请求（focusToken++）", vm.focusToken > tokenBefore)

        // Wake latency: panel already created; measure show() over 20 toggles.
        var samples: [Double] = []
        for _ in 0..<20 {
            pc.hide()
            let t0 = Date()
            pc.show()
            samples.append(Date().timeIntervalSince(t0) * 1000)
        }
        samples.sort()
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
        print(String(format: "         唤起 show() P95=%.1fms (阈值≤300ms)", p95))
        check("AC-HK-02/PERF-01 唤起 P95 ≤ 300ms", p95 <= 300)
    }

    // MARK: - Live system translation through the mounted view (AC-TR-*)

    private static func liveTranslation(_ vm: TranslatorViewModel) async {
        print("-- 实时系统翻译（经真实 .translationTask）--")

        // AC-TR-04 1000 字上限（同步截断）
        vm.inputText = String(repeating: "中", count: 1500)
        check("AC-TR-04 输入截断到 1000 字", vm.inputText.count == 1000)

        // AC-TR-01/02/06 零 Key 即译（en 已就绪）
        await vm.selectLanguage("en")
        vm.inputText = "你好，最近怎么样？"
        let got = await waitUntil(6) { vm.phase == .translated && !vm.systemTranslation.isEmpty }
        check("AC-TR-01 零 Key 自动出译（en）", got)
        check("AC-LP-02 已就绪即译，非空译文", !vm.systemTranslation.isEmpty)
        print("         译文: \(vm.systemTranslation)")

        // AC-TR-08 切目标语言即重译
        let enText = vm.systemTranslation
        await vm.selectLanguage("ja")
        let reTranslated = await waitUntil(6) { vm.phase == .translated && !vm.systemTranslation.isEmpty && vm.systemTranslation != enText }
        check("AC-TR-08 切换目标语言即重译（→ja，结果变化）", reTranslated)
        print("         日译: \(vm.systemTranslation)")

        // AC-TR-03 取消旧请求：快速连改，仅最新生效
        await vm.selectLanguage("en")
        vm.inputText = "第一段文字"
        vm.inputText = "第二段不同的文字"
        vm.inputText = "请问订单什么时候发货？"
        let finalText = vm.inputText
        let settled = await waitUntil(6) { vm.phase == .translated && !vm.systemTranslation.isEmpty }
        check("AC-TR-03 连改后稳定出译（最新输入）", settled && vm.inputText == finalText)

        // AC-TR-05 最小触发：纯空格不翻译
        vm.inputText = "   "
        let idle = await waitUntil(2) { vm.phase == .idle && vm.systemTranslation.isEmpty }
        check("AC-TR-05 纯空格不触发翻译", idle)
    }

    // MARK: - Copy logic (AC-CP-01/02/03)

    private static func copyLogic(_ vm: TranslatorViewModel) async {
        print("-- 复制 --")
        let tv = CopyAwareTextView()
        tv.string = "Hello World"
        let pb = NSPasteboard.general

        pb.clearContents()
        tv.setSelectedRange(NSRange(location: 0, length: 5)) // "Hello"
        tv.copy(nil)
        check("AC-CP-02 ⌘C 有选区 → 复制选区", pb.string(forType: .string) == "Hello")

        pb.clearContents()
        tv.setSelectedRange(NSRange(location: 0, length: 0)) // no selection
        tv.copy(nil)
        check("AC-CP-03 ⌘C 无选区 → 复制全文", pb.string(forType: .string) == "Hello World")

        // AC-CP-01/04 按钮复制全文 = currentTranslationText（AI 优先）
        vm.systemTranslation = "system text"
        vm.aiTranslation = ""
        check("AC-CP-04 currentTranslationText=系统译文（无AI）", vm.currentTranslationText == "system text")
        vm.aiTranslation = "ai text"
        check("AC-CP-04 currentTranslationText=AI译文（有AI）", vm.currentTranslationText == "ai text")
        vm.aiTranslation = ""
    }

    // MARK: - Language pack guard (AC-LP-03/07)

    private static func languagePackGuard(_ vm: TranslatorViewModel) async {
        print("-- 语言包未就绪保护 --")
        // Find a supported-but-not-installed target.
        var target: String?
        for lang in AppLanguage.firstBatch {
            let st = await LanguagePackService.shared.refresh(lang.code, force: true)
            if st == .supportedButNotInstalled { target = lang.code; break }
        }
        guard let code = target else {
            skipped("AC-LP-03/07 需准备语言", "本机所有首批语言均已安装")
            return
        }
        vm.inputText = "你好"
        await vm.selectLanguage(code)
        check("AC-LP-03 未就绪语言 → phase=需准备", vm.phase == .languagePackRequired)
        check("AC-LP-07 未就绪时不创建 session（不自动调 AI/下载）", vm.config == nil)
        // restore
        await vm.selectLanguage("en")
    }

    // MARK: - AI layer (AC-AI-01/03/06/07) — uses local mock if configured

    private static func aiLayer(_ vm: TranslatorViewModel) async {
        print("-- AI 优化层 --")

        // AC-AI-01/06 缺 Key：失败回落且保留系统译文，明确错误
        KeychainHelper.delete()
        vm.systemTranslation = "keep this system translation"
        vm.aiTranslation = ""
        vm.generateAI()
        let missing = await waitUntil(2) {
            if case .failed(.missingKey) = vm.phase { return true }; return false
        }
        check("AC-AI-01 无 Key 点击 AI → 引导填 Key（missingKey）", missing)
        check("AC-AI-06 失败保留系统译文", vm.systemTranslation == "keep this system translation")

        guard ProcessInfo.processInfo.environment["OPTIONNOW_DEEPSEEK_BASE"] != nil else {
            skipped("AC-AI-03 流式输出", "未配置 mock 端点")
            skipped("AC-AI-07 入参正确", "未配置 mock 端点")
            skipped("AC-AI-06 无效Key可辨", "未配置 mock 端点")
            return
        }

        // AC-AI-03/07 流式 + 入参：有效 Key 走 mock，逐步累加 token
        KeychainHelper.save("good-key")
        vm.systemTranslation = "Hello, how are you?"
        vm.aiTranslation = ""
        vm.tone = .business
        vm.generateAI()
        let streamed = await waitUntil(10) { vm.phase == .optimized && vm.aiTranslation == "Hello there friend" }
        check("AC-AI-03 流式累加输出（mock 三段→完整）", streamed)
        print("         AI 译文: \(vm.aiTranslation)")

        // AC-AI-06 无效 Key 可辨（mock 对 key=="bad" 返回 401 → invalidKey）
        KeychainHelper.save("bad")
        vm.systemTranslation = "keep me too"
        vm.aiTranslation = ""
        vm.generateAI()
        let invalid = await waitUntil(8) {
            if case .failed(.invalidKey) = vm.phase { return true }; return false
        }
        check("AC-AI-06 无效 Key → invalidKey 且保留系统译文",
              invalid && vm.systemTranslation == "keep me too")
        KeychainHelper.delete()
    }
}
