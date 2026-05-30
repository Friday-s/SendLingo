import Foundation
import SwiftUI
import AppKit
import Translation

/// Orchestrates the two-layer translation pipeline (PRD §8.2 / §13.4).
///
/// - Debounces input 200ms, cancels stale work (AC-TR-02/03).
/// - Drives the system translation via a `TranslationSession.Configuration` consumed
///   by the view's `.translationTask`; re-runs through `invalidate()`.
/// - Never auto-downloads a pack or auto-calls AI when a pack is missing (AC-LP-07).
/// - Wraps system translation in a 3s timeout (FIX-5 / AC-TR-07).
@MainActor
final class TranslatorViewModel: ObservableObject {
    static let inputCharLimit = 1000

    // Inputs
    @Published var inputText: String = "" { didSet { onInputChanged(oldValue) } }
    @Published var targetLanguage: String
    @Published var tone: Tone

    // Outputs / state
    @Published var systemTranslation: String = ""
    @Published var aiTranslation: String = ""
    @Published var phase: TranslationPhase = .idle
    @Published var currentStatus: LocalLanguageStatus = .unknown
    @Published var isShowingHistory: Bool = false

    /// Drives `.translationTask` in the view. Setting a new instance (new pair) or
    /// calling `invalidate()` re-runs the translation action.
    @Published var config: TranslationSession.Configuration?
    private var configuredTargetCode: String?

    // Back-translation (回译校验): translate the displayed result back to Chinese so a
    // non-native user can verify meaning/tone before sending. Lazy — only created on tap.
    @Published var backTranslation: String = ""
    @Published var backError: String?
    @Published var isBackTranslating: Bool = false
    @Published var backConfig: TranslationSession.Configuration?
    private var backConfiguredCode: String?
    private var pendingBackText: String = ""

    /// Bumped to ask the view to focus the input field (AC-HK-01).
    @Published var focusToken: Int = 0
    /// Bumped ONLY when `inputText` is changed externally (history refill, 1000-char
    /// trim) so the text view re-syncs. The view never overwrites the field on normal
    /// typing — that round-trip is what dropped characters when typing fast.
    @Published var inputResetToken: Int = 0
    /// Bumped when AI polish completes — asks the view to focus & select the AI result
    /// so ⌘A / ⌘C copy the polished text.
    @Published var aiResultFocusToken: Int = 0

    private let settings = SettingsStore.shared
    private let history = HistoryStore.shared
    private let languageService = LanguagePackService.shared

    private var debounceTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var slowTimerTask: Task<Void, Never>?
    private var pendingPrepare = false

    init() {
        let s = SettingsStore.shared
        self.targetLanguage = s.defaultTargetLanguage
        self.tone = s.defaultTone
        // Resolve initial language status & arm the config for the default language.
        Task { await selectLanguage(s.defaultTargetLanguage, retranslate: false) }
    }

    // MARK: - Derived

    var charCount: Int { inputText.count }
    var atCharLimit: Bool { inputText.count >= Self.inputCharLimit }

    /// The text that "复制" / ⌘C operate on: AI result if present, else system (AC-CP-04).
    var currentTranslationText: String {
        aiTranslation.isEmpty ? systemTranslation : aiTranslation
    }

    var errorMessage: String? {
        if case .failed(let e) = phase { return e.userMessage }
        return nil
    }

    var canUseAI: Bool {
        settings.aiEnabled && CredentialStore.hasKey && !systemTranslation.isEmpty
    }

    func requestFocus() { focusToken &+= 1 }

    // MARK: - Input handling (AC-TR-02/03/04/05)

    private func onInputChanged(_ oldValue: String) {
        // Enforce the 1000-char cap defensively (the view also limits) (AC-TR-04).
        if inputText.count > Self.inputCharLimit {
            inputText = String(inputText.prefix(Self.inputCharLimit))
            inputResetToken &+= 1 // external truncation → re-sync the field
            return // didSet will fire again with the trimmed value
        }

        aiTask?.cancel()
        debounceTask?.cancel()
        clearBack() // any prior back-translation is now stale

        guard isMeaningful(inputText) else {
            // Empty / whitespace / single punctuation → no translation (AC-TR-05/ERR-01).
            systemTranslation = ""
            aiTranslation = ""
            if currentStatus.isSelectable, currentStatus != .supportedButNotInstalled {
                phase = .idle
            }
            return
        }

        let delay = UInt64(max(0, settings.debounceMs)) * 1_000_000
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            await self.triggerTranslate()
        }
    }

    private func isMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Require at least one letter (covers CJK) or number; a lone punctuation does not count.
        return trimmed.contains { $0.isLetter || $0.isNumber }
    }

    // MARK: - Language selection (AC-TR-08 / AC-LP-*)

    func selectLanguage(_ code: String, retranslate: Bool = true) async {
        targetLanguage = code
        aiTranslation = ""
        clearBack()
        let status = await languageService.refresh(code)
        currentStatus = status

        switch status {
        case .installed:
            if isMeaningful(inputText) {
                if retranslate { triggerTranslateNow() } // arms config lazily
            } else {
                // Defer session creation (and the ~70MB system model load) until the
                // user actually types — keeps an open-but-idle panel lightweight (AC-PERF-05).
                config = nil
                configuredTargetCode = nil
                phase = .idle
            }
        case .supportedButNotInstalled:
            // Do NOT set a config → no auto-download, no auto-AI (AC-LP-03/07).
            config = nil
            configuredTargetCode = nil
            phase = .languagePackRequired
        case .unsupported:
            config = nil
            phase = .failed(.unsupported)
        case .systemUnavailable:
            config = nil
            phase = .failed(.systemVersionUnsupported)
        case .preparing, .unknown:
            break
        }
    }

    private func armConfig(for code: String) {
        if configuredTargetCode != code || config == nil {
            config = TranslationSession.Configuration(
                source: Locale.Language(identifier: AppLanguage.source.code),
                target: Locale.Language(identifier: code))
            configuredTargetCode = code
        }
    }

    // MARK: - Trigger translation

    private func triggerTranslate() async {
        let status = await languageService.refresh(targetLanguage)
        currentStatus = status
        switch status {
        case .installed:
            triggerTranslateNow()
        case .supportedButNotInstalled:
            config = nil
            configuredTargetCode = nil
            phase = .languagePackRequired
        case .unsupported:
            phase = .failed(.unsupported)
        case .systemUnavailable:
            phase = .failed(.systemVersionUnsupported)
        case .preparing, .unknown:
            break
        }
    }

    /// Ensures the config is armed for the current language and (re)runs translation.
    private func triggerTranslateNow() {
        if configuredTargetCode != targetLanguage || config == nil {
            armConfig(for: targetLanguage)   // new instance → .translationTask runs
        } else {
            config?.invalidate()             // same pair → re-run with latest text
        }
    }

    // MARK: - Language-pack preparation (AC-LP-04/05/06)

    func prepareLanguagePack() {
        pendingPrepare = true
        currentStatus = .preparing
        languageService.markPreparing(targetLanguage)
        phase = .preparingLanguagePack
        if configuredTargetCode != targetLanguage || config == nil {
            armConfig(for: targetLanguage)
        } else {
            config?.invalidate()
        }
    }

    // MARK: - Session callback (driven by the view's nonisolated .translationTask)

    /// `TranslationSession` is a non-Sendable, non-isolated class. We therefore keep
    /// all calls that touch `session` in this nonisolated method and hop to the main
    /// actor only to read/write UI state (passing Sendable values). This is what lets
    /// the session stay within a single isolation region (Swift 6 strict concurrency).
    nonisolated func onSession(_ session: TranslationSession) async {
        if await consumePendingPrepare() {
            await setPhase(.preparingLanguagePack)
            do {
                try await session.prepareTranslation()
                await markPrepared()
            } catch {
                await markPrepareFailed()
                return
            }
        }
        await runTranslation(session)
    }

    private nonisolated func runTranslation(_ session: TranslationSession) async {
        guard let text = await beginTranslationIfNeeded() else { return }
        do {
            let result = try await session.translate(text).targetText
            await finishTranslation(forText: text, result: result)
        } catch {
            await failTranslation(message: error.localizedDescription)
        }
    }

    // MARK: - Main-actor state transitions for the session pipeline

    private func consumePendingPrepare() -> Bool {
        let p = pendingPrepare
        pendingPrepare = false
        return p
    }

    private func setPhase(_ p: TranslationPhase) { phase = p }

    private func markPrepared() {
        languageService.markInstalled(targetLanguage)
        currentStatus = .installed
    }

    private func markPrepareFailed() async {
        // Download cancelled / failed → back to "需准备" (AC-LP-06).
        currentStatus = .supportedButNotInstalled
        phase = .languagePackRequired
        await languageService.refresh(targetLanguage, force: true)
    }

    /// Returns the text to translate (and arms the 3s slow-timer), or nil to skip.
    private func beginTranslationIfNeeded() -> String? {
        let text = inputText
        guard isMeaningful(text) else { phase = .idle; return nil }
        phase = .translating
        startSlowTimer(for: text)
        return text
    }

    /// FIX-5 / AC-TR-07: if a translation has not returned within 3s, surface the
    /// "翻译较慢" message (without blanking or crashing). A later result overrides it.
    private func startSlowTimer(for text: String) {
        slowTimerTask?.cancel()
        slowTimerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.phase == .translating, self.inputText == text {
                self.phase = .failed(.translationSlowTimeout)
            }
        }
    }

    private func finishTranslation(forText text: String, result: String) {
        slowTimerTask?.cancel()
        // Drop stale results if the input has since changed (AC-TR-03).
        guard text == inputText else { return }
        systemTranslation = result
        aiTranslation = ""
        phase = .translated
        recordHistory(ai: nil)
    }

    private func failTranslation(message: String) {
        slowTimerTask?.cancel()
        phase = .failed(.systemTranslationFailed(message))
    }

    // MARK: - AI optimization (AC-AI-02/03/06/07)

    /// Entry point for the ⌥↵ shortcut and the AI button: optimize, or guide the user
    /// to fill a key if none is configured.
    func requestAI() {
        guard settings.aiEnabled else { return }
        guard CredentialStore.hasKey else {
            phase = .failed(.missingKey)
            NotificationCenter.default.post(name: .optionNowOpenSettings, object: nil)
            return
        }
        guard !systemTranslation.isEmpty else { return }
        generateAI()
    }

    func generateAI() {
        guard settings.aiEnabled else { return }
        guard let key = CredentialStore.load(),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .failed(.missingKey)
            return
        }
        guard !systemTranslation.isEmpty else { return }

        let source = inputText
        let system = systemTranslation
        let langDisplay = AppLanguage.named(targetLanguage).displayName
        let tone = self.tone
        let model = settings.deepseekModel

        aiTranslation = ""
        clearBack()
        phase = .optimizing
        aiTask?.cancel()
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = AIOptimizeService.shared.optimize(
                source: source,
                systemTranslation: system,
                targetLanguageDisplay: langDisplay,
                tone: tone,
                apiKey: key,
                model: model)
            do {
                for try await delta in stream {
                    if Task.isCancelled { return }
                    self.aiTranslation += delta
                }
                guard !Task.isCancelled else { return }
                self.phase = .optimized
                self.recordHistory(ai: self.aiTranslation)
                self.aiResultFocusToken &+= 1 // focus & select AI result for ⌘A/⌘C
            } catch let e as TranslationError {
                // Keep the system translation visible on failure (AC-AI-06).
                self.aiTranslation = ""
                self.phase = .failed(e)
            } catch {
                self.aiTranslation = ""
                self.phase = .failed(.providerError(error.localizedDescription))
            }
        }
    }

    // MARK: - Back-translation (回译校验)

    /// Translate the displayed result (AI if present, else system) back to Chinese so
    /// the user can verify it before sending. Reverse pair: targetLanguage -> zh-Hans.
    func backTranslate() {
        let text = currentTranslationText
        guard !text.isEmpty else { return }
        pendingBackText = text
        backTranslation = ""
        backError = nil
        isBackTranslating = true
        if backConfiguredCode != targetLanguage || backConfig == nil {
            backConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: targetLanguage),
                target: Locale.Language(identifier: AppLanguage.source.code))
            backConfiguredCode = targetLanguage
        } else {
            backConfig?.invalidate()
        }
    }

    /// Driven by the view's second `.translationTask` (nonisolated, like `onSession`).
    nonisolated func onBackSession(_ session: TranslationSession) async {
        let text = await pendingBackTextValue()
        guard !text.isEmpty else { await finishBack(result: nil); return }
        do {
            let result = try await session.translate(text).targetText
            await finishBack(result: result)
        } catch {
            await finishBack(result: nil)
        }
    }

    private func pendingBackTextValue() -> String { pendingBackText }

    private func finishBack(result: String?) {
        isBackTranslating = false
        if let result {
            backTranslation = result
        } else {
            backError = "暂无法回译（可能缺少该语言到中文的本地语言包）"
        }
    }

    private func clearBack() {
        backTranslation = ""
        backError = nil
        isBackTranslating = false
    }

    // MARK: - History (AC-HS-*)

    private func recordHistory(ai: String?) {
        guard !systemTranslation.isEmpty, isMeaningful(inputText) else { return }
        history.add(TranslationHistoryItem(
            sourceText: inputText,
            targetLanguage: targetLanguage,
            systemTranslation: systemTranslation,
            aiTranslation: ai,
            tone: tone.rawValue))
    }

    /// Click a history row → refill Chinese & re-translate; do NOT restore AI (FIX-7).
    func applyHistory(_ item: TranslationHistoryItem) {
        isShowingHistory = false
        aiTranslation = ""
        systemTranslation = ""
        tone = Tone(rawValue: item.tone ?? "") ?? tone
        inputText = item.sourceText
        inputResetToken &+= 1 // external refill → re-sync the field
        Task { await selectLanguage(item.targetLanguage, retranslate: true) }
    }

    /// Copy the current translation result (AI if present, else system) to the
    /// clipboard. Used by ⌘C (no selection) and the copy button. Returns false if
    /// there is nothing to copy.
    @discardableResult
    func copyResultToPasteboard() -> Bool {
        let text = currentTranslationText
        guard !text.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        commitCurrentToHistory()
        NotificationCenter.default.post(name: .optionNowResultCopied, object: nil)
        return true
    }

    func commitCurrentToHistory() {
        guard phase == .translated || phase == .optimized else { return }
        recordHistory(ai: aiTranslation.isEmpty ? nil : aiTranslation)
    }
}
