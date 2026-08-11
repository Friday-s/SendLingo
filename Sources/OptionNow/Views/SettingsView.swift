import SwiftUI

/// Settings page (PRD §7.7 / AC-ST-*). Holds no API key directly — the key lives in
/// a local credential file (see `CredentialStore`).
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var langService: LanguagePackService

    @State private var keyInput = ""
    @State private var keyPresent = CredentialStore.hasKey
    @State private var validating = false
    @State private var keyMessage: (text: String, ok: Bool)?

    var body: some View {
        Form {
            generalSection
            aiSection
            languagePackSection
            historySection
            appearanceSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 520, maxWidth: .infinity,
               minHeight: 520, maxHeight: .infinity)
        .task { await langService.refreshAll(force: false) }
    }

    // MARK: - General (AC-ST-02/03/05, AC-HK-06/07)

    private var generalSection: some View {
        Section("通用") {
            Picker("默认目标语言", selection: $settings.defaultTargetLanguage) {
                ForEach(AppLanguage.firstBatch) { Text($0.displayName).tag($0.code) }
            }
            Picker("默认语气", selection: $settings.defaultTone) {
                ForEach(Tone.allCases) { Text($0.displayName).tag($0) }
            }
            HStack {
                Text("全局快捷键")
                Spacer()
                HotKeyRecorder()
            }
            if settings.hotkeyConflict {
                Label("该快捷键注册失败（可能被系统或其他 App 占用），请更换",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - AI (AC-ST-01/04, AC-AI-01/08)

    private var aiSection: some View {
        Section("AI 优化（DeepSeek · 可选）") {
            Toggle("显示 AI 优化入口", isOn: $settings.aiEnabled)

            HStack(spacing: 6) {
                SecureField("DeepSeek API Key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                Button("粘贴") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        keyInput = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            // Model selection (AC-AI / 让用户选择 DeepSeek 模型而非写死)
            HStack(spacing: 6) {
                TextField("模型 ID", text: $settings.deepseekModel)
                    .textFieldStyle(.roundedBorder)
                Menu("常用") {
                    Button("deepseek-chat（快速 · 推荐）") { settings.deepseekModel = "deepseek-chat" }
                    Button("deepseek-reasoner（推理）") { settings.deepseekModel = "deepseek-reasoner" }
                }
                .fixedSize()
            }
            Text("填写 DeepSeek 账号支持的模型 ID。deepseek-chat 为快速（非推理）模型；如需特定版本（如 fast / 某代号）按服务商命名填入即可。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                Button("保存") { saveKey() }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("验证") { Task { await validateKey() } }
                    .disabled(validating || (!keyPresent && keyInput.trimmingCharacters(in: .whitespaces).isEmpty))
                Button("删除", role: .destructive) { deleteKey() }
                    .disabled(!keyPresent)
                if validating { ProgressView().controlSize(.small) }
                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: keyPresent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(keyPresent ? .green : .secondary)
                Text(keyPresent ? "已保存（本地，跨更新保留）" : "未配置 Key（系统翻译不受影响）")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let msg = keyMessage {
                Text(msg.text)
                    .font(.system(size: 11))
                    .foregroundStyle(msg.ok ? .green : .orange)
            }

            Text("启用 AI 优化时，当前中文与系统译文会发送给你配置的 DeepSeek 服务。默认系统翻译不需要第三方 API Key。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Language packs (AC-ST-06 / AC-LP-01)

    private var languagePackSection: some View {
        Section {
            ForEach(AppLanguage.firstBatch) { lang in
                HStack {
                    Text(lang.displayName).font(.system(size: 12))
                    Spacer()
                    Text(langService.cachedStatus(for: lang.code).shortLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(langService.cachedStatus(for: lang.code) == .installed ? .green : .secondary)
                }
            }
        } header: {
            HStack {
                Text("本地语言包状态")
                Spacer()
                Button("刷新") { Task { await langService.refreshAll() } }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
        }
    }

    // MARK: - History (AC-ST / P1)

    private var historySection: some View {
        Section("历史记录") {
            Toggle("保存翻译历史（仅本地）", isOn: $settings.historyEnabled)
            Button("清空全部历史", role: .destructive) { HistoryStore.shared.clear() }
        }
    }

    // MARK: - Appearance (P1, AC-ST-07)

    private var appearanceSection: some View {
        Section("外观（高级）") {
            Picker("主题", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
            }
            HStack {
                Text("字号")
                Slider(value: $settings.fontSize, in: 11...20, step: 1)
                Text("\(Int(settings.fontSize))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 22)
            }
            Stepper("防抖时延：\(settings.debounceMs) ms",
                    value: $settings.debounceMs, in: 100...600, step: 50)
        }
    }

    // MARK: - Key actions

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if CredentialStore.save(trimmed) {
            keyPresent = true
            keyInput = ""
            keyMessage = ("已保存（本地，跨更新保留）", true)
        } else {
            keyMessage = ("保存失败，请重试", false)
        }
    }

    private func deleteKey() {
        CredentialStore.delete()
        keyPresent = CredentialStore.hasKey
        keyInput = ""
        keyMessage = ("已删除", true)
    }

    private func validateKey() async {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.isEmpty ? (CredentialStore.load() ?? "") : trimmed
        guard !key.isEmpty else { return }
        validating = true
        keyMessage = nil
        let error = await AIOptimizeService.shared.validate(apiKey: key, model: settings.deepseekModel)
        validating = false
        if let error {
            keyMessage = (error.userMessage, false)
        } else {
            keyMessage = ("Key 有效", true)
            // Persist a freshly-typed valid key for convenience.
            if !trimmed.isEmpty { saveKey() }
        }
    }
}
