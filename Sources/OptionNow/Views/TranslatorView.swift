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
        .frame(minWidth: 300, idealWidth: 420, minHeight: 300, idealHeight: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
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
        HStack(spacing: 10) {
            Text("Option Now")
                .font(.system(size: 13, weight: .semibold))
            languageMenu
            statusTag(vm.currentStatus)
            Spacer()
            iconButton("clock.arrow.circlepath", help: "历史") { vm.isShowingHistory.toggle() }
            iconButton("gearshape", help: "设置") {
                NotificationCenter.default.post(name: .optionNowOpenSettings, object: nil)
            }
            iconButton("xmark", help: "关闭") {
                NotificationCenter.default.post(name: .optionNowHide, object: nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
            HStack(spacing: 3) {
                Text(AppLanguage.named(vm.targetLanguage).displayName)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func statusTag(_ status: LocalLanguageStatus) -> some View {
        if status != .installed && status != .unknown {
            Text(status.shortLabel)
                .font(.system(size: 10))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.18), in: Capsule())
                .foregroundStyle(.orange)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Custom draggable divider between input and output. The input-pane height
            // is persisted (settings.splitInputHeight), so the divider position is
            // remembered across hide/show and restarts.
            GeometryReader { geo in
                let minInput: CGFloat = 60
                let maxInput = max(minInput, geo.size.height - 98) // keep room for output
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

    /// Thin draggable handle that resizes the input pane and persists the new height.
    /// Uses the global coordinate space so the moving handle doesn't feed back into the
    /// drag delta (which caused oscillation/flicker), and only writes the persisted
    /// value on release (live drag uses local @State).
    private func splitHandle(minInput: CGFloat, maxInput: CGFloat) -> some View {
        Divider()
            .frame(height: 11)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? CGFloat(settings.splitInputHeight)
                        if dragStartHeight == nil { dragStartHeight = start }
                        liveSplitHeight = min(max(start + value.translation.height, minInput), maxInput)
                    }
                    .onEnded { _ in
                        if let h = liveSplitHeight { settings.splitInputHeight = Double(h) }
                        dragStartHeight = nil
                        liveSplitHeight = nil
                    }
            )
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
            HStack {
                if vm.atCharLimit {
                    Text("已达 1000 字符上限")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                Spacer()
                Text("\(vm.charCount)/\(TranslatorViewModel.inputCharLimit)")
                    .font(.system(size: 10))
                    .foregroundStyle(vm.atCharLimit ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }

    // MARK: - Tone (AC-AI-04) — only relevant when AI entry is shown

    @ViewBuilder
    private var toneBar: some View {
        if settings.aiEnabled {
            HStack {
                Text("TRANSLATION").font(.system(size: 9, weight: .semibold))
                    .tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $vm.tone) {
                    ForEach(Tone.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
        } else {
            HStack {
                Text("TRANSLATION").font(.system(size: 9, weight: .semibold))
                    .tracking(1.5).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
        }
    }

    // MARK: - Translation result area

    @ViewBuilder
    private var translationArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private var preparePackView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("需要先准备该目标语言的本地语言包")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Button {
                vm.prepareLanguagePack()
            } label: {
                Label("准备语言包", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var preparingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在准备语言包…").font(.system(size: 13)).foregroundStyle(.secondary)
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
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("翻译中…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } else if vm.errorMessage == nil {
            Text("译文会在这里即时显示")
                .font(.system(size: 13)).foregroundStyle(.tertiary)
        }

        // AI optimized translation (streaming)
        if !vm.aiTranslation.isEmpty || vm.phase == .optimizing {
            HStack(spacing: 6) {
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
            HStack(spacing: 6) {
                sectionLabel("回译校验（中文）")
                if vm.isBackTranslating { ProgressView().controlSize(.mini) }
            }
            if let err = vm.backError {
                Text(err).font(.system(size: 12)).foregroundStyle(.orange)
            } else if !vm.backTranslation.isEmpty {
                SelectableTextView(text: vm.backTranslation,
                                   fontSize: settings.fontSize,
                                   textColor: .secondaryLabelColor)
                    .frame(minHeight: 32)
            }
        }

        // Error message (kept below the system translation; AC-AI-06 keeps system text)
        if let msg = vm.errorMessage {
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.top, 2)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
    }

    // MARK: - Bottom bar (PRD §9.1)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if settings.aiEnabled {
                Button(action: handleAITap) {
                    Label("AI 生成", systemImage: "sparkles")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .opacity(aiGreyed ? 0.5 : 1)
                .help(CredentialStore.hasKey ? "用 DeepSeek 优化当前译文（⌥↵）" : "填写 DeepSeek API Key 后可使用")
            }

            Button(action: { vm.backTranslate() }) {
                Label("回译", systemImage: "arrow.uturn.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .disabled(vm.currentTranslationText.isEmpty || vm.isBackTranslating)
            .help("把译文再译回中文，核对意思再发")

            Button(action: copyAll) {
                Label(showCopied ? "已复制" : "复制",
                      systemImage: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .disabled(vm.currentTranslationText.isEmpty)

            Spacer()

            Text((settings.aiEnabled ? "⌥↵ AI · " : "") + "⌘C 复制 · Esc 关闭 · \(settings.hotkey.displayString) 开关")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
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
