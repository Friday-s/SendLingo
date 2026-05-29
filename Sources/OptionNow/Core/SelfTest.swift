import AppKit

/// Headless self-test exercising the **shipping** non-UI code paths, run via
/// `OptionNow --selftest`. Provides concrete pass/fail evidence for the acceptance
/// items that don't require human interaction (Keychain/security, history rules,
/// settings defaults/round-trip, hotkey registration, error copy).
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var pass = 0, fail = 0
        func check(_ name: String, _ cond: Bool) {
            print("  [\(cond ? "PASS" : "FAIL")] \(name)")
            cond ? (pass += 1) : (fail += 1)
        }

        print("==== Option Now self-test ====")

        // --- Keychain (AC-SEC-01 / AC-ST-01) ---
        KeychainHelper.delete()
        let saved = KeychainHelper.save("sk-selftest-ABC123")
        check("Keychain save", saved)
        check("Keychain load round-trip", KeychainHelper.load() == "sk-selftest-ABC123")
        check("Keychain hasKey true", KeychainHelper.hasKey)
        KeychainHelper.delete()
        check("Keychain delete clears", KeychainHelper.load() == nil && !KeychainHelper.hasKey)

        // --- Settings defaults reflecting the FIX-es ---
        let s = SettingsStore.shared
        check("Default tone = casual (FIX-4/AC-AI-05)", s.defaultTone == .casual)
        check("aiEnabled default true = show entry (FIX-3)", s.aiEnabled == true)
        check("Debounce default 200ms (AC-TR-02)", s.debounceMs == 200)
        check("Auto-hide-on-blur default off (AC-WIN-08)", s.autoHideOnBlur == false)
        // Round-trip
        let origLang = s.defaultTargetLanguage
        s.defaultTargetLanguage = "ja"
        check("Settings round-trip (AC-ST-02)", UserDefaults.standard.string(forKey: "defaultTargetLanguage") == "ja")
        s.defaultTargetLanguage = origLang

        // --- History rules (AC-HS-01/05) ---
        let h = HistoryStore.shared
        let savedItems = h.items
        let savedFavs = h.favorites
        h.clear()
        for f in savedFavs { h.toggleFavorite(f) } // clear favorites for a clean slate
        for i in 0..<12 {
            h.add(TranslationHistoryItem(sourceText: "消息\(i)对话内容",
                                         targetLanguage: "en",
                                         systemTranslation: "msg \(i)"))
        }
        check("Recent history capped at 10 (AC-HS-01)", h.items.count == 10)
        h.clear()
        h.add(TranslationHistoryItem(sourceText: "你", targetLanguage: "en", systemTranslation: "you"))
        h.add(TranslationHistoryItem(sourceText: "你好", targetLanguage: "en", systemTranslation: "hi"))
        h.add(TranslationHistoryItem(sourceText: "你好吗", targetLanguage: "en", systemTranslation: "how are you"))
        check("Editing-session collapse → 1 entry", h.items.count == 1 && h.items.first?.sourceText == "你好吗")
        h.add(TranslationHistoryItem(sourceText: "明天见", targetLanguage: "en", systemTranslation: "see you"))
        check("Distinct message → new entry", h.items.count == 2)
        if let top = h.items.first { h.delete(top) }
        check("Single delete (AC-HS-05)", h.items.count == 1)

        // --- Favorites: pin/unpin, max 3, move recent↔favorites ---
        h.clear()
        for f in h.favorites { h.toggleFavorite(f) }
        var made: [TranslationHistoryItem] = []
        for i in 0..<5 {
            let it = TranslationHistoryItem(sourceText: "收藏候选\(i)", targetLanguage: "en", systemTranslation: "fav \(i)")
            made.append(it); h.add(it)
        }
        h.toggleFavorite(made[4]); h.toggleFavorite(made[3]); h.toggleFavorite(made[2])
        check("Favorite pins item & removes from recent", h.favorites.count == 3 && !h.items.contains { $0.id == made[4].id })
        check("Favorites capped at 3", { h.toggleFavorite(made[1]); return h.favorites.count == 3 }())
        check("Unfavorite moves back to recent", { let f = h.favorites[0]; h.toggleFavorite(f); return !h.isFavorite(f) && h.items.contains { $0.id == f.id } }())

        // restore prior state
        h.clear()
        for f in h.favorites { h.toggleFavorite(f) }
        for item in savedItems.reversed() { h.add(item) }
        for f in savedFavs { h.add(f); h.toggleFavorite(f) }

        // --- Hotkey registration (AC-HK-01 path / AC-HK-07) ---
        let okReg = HotKeyManager.shared.register(.defaultHotKey) {}
        check("Default ⌥I hotkey registers", okReg)
        HotKeyManager.shared.unregister()
        check("Hotkey display string == '⌥ I'", HotKeyConfig.defaultHotKey.displayString == "⌥ I")

        // --- Tone differences feed AI tone switch (AC-AI-04) ---
        let mods = Set(Tone.allCases.map { $0.promptModifier })
        check("Three distinct tone prompt modifiers", mods.count == 3)

        // --- Error copy (AC-ERR-07/08, AC-TR-07) ---
        check("Invalid-key copy", TranslationError.invalidKey.userMessage.contains("无效"))
        check("Rate-limit copy", TranslationError.rateLimited.userMessage.contains("重试"))
        check("Slow-timeout copy (FIX-5)", TranslationError.translationSlowTimeout.userMessage.contains("翻译较慢"))
        check("Missing-key copy (AC-AI-01)", TranslationError.missingKey.userMessage.contains("API Key"))

        print("==== \(pass) passed, \(fail) failed ====")
        return fail == 0 ? 0 : 1
    }
}
