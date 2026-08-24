import SwiftUI
import AppKit
import Translation

struct TranslatorView: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var langService: LanguagePackService

    @State private var showCopied = false
    @State private var dragStartHeight: CGFloat?
    @State private var liveSplitHeight: CGFloat?  // non-nil only while dragging

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if vm.isShowingHistory {
                HistoryPanel(onClose: { vm.isShowingHistory = false })
            } else {
                mainContent
            }
        }
        .frame(minWidth: 340, idealWidth: 420, minHeight: 360, idealHeight: 560)
        // Family panel chrome: native glass, hairline edge, one diffuse shadow —
        // the same recipe as the OptionNow dial and the Orbit menu-bar panel.
        .dsPanel()
        .preferredColorScheme(settings.theme.colorScheme)
        // System translation is driven here: a new config (or invalidate) re-runs this.
        // The action is marked @Sendable so it is nonisolated — the non-Sendable
        // `session` then stays in one isolation region (it never crosses to the main
        // actor), which is what Swift 6 strict concurrency requires.
        .translationTask(vm.config) { @Sendable session in
            await vm.onSession(session)
        }
        // Second task drives back-translation (目标语 → 中文) for 回译校验.
        .translationTask(vm.backConfig) { @Sendable session in
            await vm.onBackSession(session)
        }
        .onAppear {
            vm.requestFocus()
            Task { await langService.refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .optionNowResultCopied)) { _ in
            flashCopied()
        }
    }

    /// Briefly show the "已复制" state on the copy button.
    private func flashCopied() {
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopied = false }
    }

    // MARK: - Top bar (PRD §9.1)

    private var topBar: some View {
        HStack(spacing: DS.Space.sm) {
            Text("SendLingo")
                .font(DS.Font.h4())
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            languageMenu
            statusTag(vm.currentStatus)
            Spacer(minLength: DS.Space.xs)
            iconButton("clock.arrow.circlepath", help: "历史") { vm.isShowingHistory.toggle() }
            iconButton("gearshape", help: "设置") {
                NotificationCenter.default.post(name: .optionNowOpenSettings, object: nil)
            }
            iconButton("xmark", help: "关闭") {
                NotificationCenter.default.post(name: .optionNowHide, object: nil)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.firstBatch) { lang in
                let status = langService.cachedStatus(for: lang.code)
                Button {
                    Task { await vm.selectLanguage(lang.code) }
                } label: {
                    Text("\(lang.displayName)  ·  \(status.shortLabel)")
                }
                .disabled(!status.isSelectable)
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(AppLanguage.named(vm.targetLanguage).displayName)
                    .font(DS.Font.caption(.medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(DS.Color.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func statusTag(_ status: LocalLanguageStatus) -> some View {
        if status != .installed && status != .unknown {
            DSBadge(text: status.shortLabel, tint: DS.Color.warning)
                .fixedSize()
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(DSIconButtonStyle(size: 24))
        .help(help)
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Custom draggable divider between input and output. The input-pane height
            // is persisted (settings.splitInputHeight), so the divider position is
            // remembered across hide/show and restarts.
            GeometryReader { geo in
                // The input pane scales within the available height while always
                // reserving a useful translation area. This keeps both panes usable
                // when the user makes the window short or tall.
                let minInput = min(84, max(56, geo.size.height * 0.18))
                let reservedOutput = min(180, max(112, geo.size.height * 0.42))
                let maxInput = max(minInput, geo.size.height - reservedOutput - 11)
                let base = liveSplitHeight ?? CGFloat(settings.splitInputHeight)
                let inputH = min(max(base, minInput), maxInput)
                VStack(spacing: 0) {
                    inputArea
                        .frame(height: inputH)
                    splitHandle(minInput: minInput, maxInput: maxInput)
                    VStack(spacing: 0) {
                        toneBar
                        translationArea
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            Divider()
            bottomBar
        }
        .onExitCommand {
            NotificationCenter.default.post(name: .optionNowHide, object: nil)
        }
    }

    /// Native resize handle (does not move the window; see `SplitHandle`). The live
    /// drag uses local @State; the persisted value is written on release.
    private func splitHandle(minInput: CGFloat, maxInput: CGFloat) -> some View {
        SplitHandle(
            onChanged: { delta in
                let start = dragStartHeight ?? CGFloat(settings.splitInputHeight)
                if dragStartHeight == nil { dragStartHeight = start }
                liveSplitHeight = min(max(start + delta, minInput), maxInput)
            },
            onEnded: {
                if let h = liveSplitHeight { settings.splitInputHeight = Double(h) }
                dragStartHeight = nil
                liveSplitHeight = nil
            }
        )
        .frame(height: 11)
    }

    // MARK: - Input (AC-TR-04 / AC-ERR-01/02)

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            ChineseInputView(text: $vm.inputText,
                             fontSize: settings.fontSize,
                             placeholder: "输入中文，实时转换为目标语言",
                             focusToken: vm.focusToken,
                             resetToken: vm.inputResetToken,
                             resultProvider: { vm.currentTranslationText },
                             onCopyResult: { onResultCopied() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: DS.Space.sm) {
                if vm.atCharLimit {
                    Text("已达 1000 字符上限")
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.warning)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.xs)
                Text("\(vm.charCount)/\(TranslatorViewModel.inputCharLimit)")
                    .font(DS.Font.caption().monospacedDigit())
                    .foregroundStyle(vm.atCharLimit ? DS.Color.warning : DS.Color.textSecondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, DS.Space.md).padding(.top, DS.Space.sm)
    }

    // MARK: - Tone (AC-AI-04) — only relevant when AI entry is shown

    @ViewBuilder
    private var toneBar: some View {
        if settings.aiEnabled {
            HStack(spacing: DS.Space.sm) {
                eyebrowLabel
                Spacer(minLength: DS.Space.xs)
                Picker("", selection: $vm.tone) {
                    ForEach(Tone.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 150, maxWidth: 220)
                .layoutPriority(1)
            }
            .padding(.horizontal, DS.Space.md).padding(.top, DS.Space.md).padding(.bottom, 2)
        } else {
            HStack {
                eyebrowLabel
                Spacer()
            }
            .padding(.horizontal, DS.Space.md).padding(.top, DS.Space.md).padding(.bottom, 2)
        }
    }

    /// Accent eyebrow — the same treatment `DSSectionHeader` uses family-wide.
    private var eyebrowLabel: some View {
        Text("TRANSLATION")
            .font(DS.Font.caption(.semibold))
            .tracking(1.2)
            .foregroundStyle(DS.Color.accent)
            .fixedSize()
    }

    // MARK: - Translation result area

    @ViewBuilder
    private var translationArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                switch vm.phase {
                case .languagePackRequired:
                    preparePackView
                case .preparingLanguagePack:
                    preparingView
                default:
                    resultView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
        }
        .frame(maxHeight: .infinity)
    }

    private var preparePackView: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("需要先准备该目标语言的本地语言包")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                vm.prepareLanguagePack()
            } label: {
                Label("准备语言包", systemImage: "arrow.down.circle")
            }
            .buttonStyle(DSPrimaryButtonStyle())
        }
    }

    private var preparingView: some View {
        HStack(spacing: DS.Space.sm) {
            ProgressView().controlSize(.small)
            Text("正在准备语言包…")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        // System translation
        if !vm.systemTranslation.isEmpty {
            sectionLabel("系统译文")
            SelectableTextView(text: vm.systemTranslation, fontSize: settings.fontSize)
                .frame(minHeight: 40)
        } else if vm.phase == .translating {
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text("翻译中…")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.textSecondary)
            }
        } else if vm.errorMessage == nil {
            Text("译文会在这里即时显示")
                .font(DS.Font.body())
                .foregroundStyle(DS.Color.textTertiary)
        }

        // AI optimized translation (streaming)
        if !vm.aiTranslation.isEmpty || vm.phase == .optimizing {
            HStack(spacing: DS.Space.xs) {
                sectionLabel("AI 优化译文")
                if vm.phase == .optimizing {
                    ProgressView().controlSize(.mini)
                }
            }
            SelectableTextView(text: vm.aiTranslation,
                               fontSize: settings.fontSize,
                               focusToken: vm.aiResultFocusToken)
                .frame(minHeight: 40)
        }

        // Back-translation (回译校验) — verify the meaning of what you're about to send.
        if vm.isBackTranslating || !vm.backTranslation.isEmpty || vm.backError != nil {
            HStack(spacing: DS.Space.xs) {
                sectionLabel("回译校验（中文）")
                if vm.isBackTranslating { ProgressView().controlSize(.mini) }
            }
            if let err = vm.backError {
                Text(err)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !vm.backTranslation.isEmpty {
                SelectableTextView(text: vm.backTranslation,
                                   fontSize: settings.fontSize,
                                   textColor: .secondaryLabelColor,
                                   minimumHeight: 32)
                    .frame(minHeight: 32)
            }
        }

        // Error message (kept below the system translation; AC-AI-06 keeps system text)
        if let msg = vm.errorMessage {
            Text(msg)
                .font(DS.Font.caption())
                .foregroundStyle(DS.Color.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.caption(.medium))
            .foregroundStyle(DS.Color.textSecondary)
    }

    // MARK: - Bottom bar (PRD §9.1)

    private var bottomBar: some View {
        // Narrow windows drop the hint rather than the actions, so the primary
        // buttons are never clipped.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.sm) {
                actionButtons
                Spacer(minLength: DS.Space.sm)
                shortcutHint
            }

            HStack(spacing: DS.Space.sm) {
                actionButtons
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.sm)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if settings.aiEnabled {
            Button(action: handleAITap) {
                Label("AI 生成", systemImage: "sparkles")
            }
            .buttonStyle(DSSecondaryButtonStyle())
            .opacity(aiGreyed ? 0.5 : 1)
            .fixedSize()
            .help(CredentialStore.hasKey ? "用 DeepSeek 优化当前译文（⌥↵）" : "填写 DeepSeek API Key 后可使用")
        }

        Button(action: { vm.backTranslate() }) {
            Label("回译", systemImage: "arrow.uturn.left")
        }
        .buttonStyle(DSSecondaryButtonStyle())
        .fixedSize()
        .disabled(vm.currentTranslationText.isEmpty || vm.isBackTranslating)
        .help("把译文再译回中文，核对意思再发")

        Button(action: copyAll) {
            Label(showCopied ? "已复制" : "复制",
                  systemImage: showCopied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(DSSecondaryButtonStyle(tint: showCopied ? DS.Color.success : nil))
        .fixedSize()
        .disabled(vm.currentTranslationText.isEmpty)
    }

    private var shortcutHint: some View {
        Text((settings.aiEnabled ? "⌥↵ AI · " : "") + "⌘C 复制 · Esc 关闭 · \(settings.hotkey.displayString) 开关")
            .font(DS.Font.caption())
            .foregroundStyle(DS.Color.textTertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var aiGreyed: Bool {
        !CredentialStore.hasKey || vm.systemTranslation.isEmpty
    }

    private func handleAITap() { vm.requestAI() }

    private func copyAll() {
        let text = vm.currentTranslationText
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        onResultCopied()
    }

    /// Shared "已复制" feedback (button and ⌘C-from-input both use this).
    private func onResultCopied() {
        vm.commitCurrentToHistory()
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showCopied = false
        }
    }
}
