# Option Now

> 中文写，地道发 —— 一个常驻 macOS 菜单栏的「中文输入即译」浮窗工具。

按 **⌥ I** 唤起浮窗，用中文输入，停顿即出目标语言译文。默认走 **macOS 系统翻译框架 + 本地语言包**，零配置、无需任何第三方 API Key；需要更自然的表达时，可选用 **DeepSeek（自带 Key）** 做 AI 润色。结果仅复制到剪贴板，不自动粘贴、不替换选区。

专注一个场景做到顺手：在邮件、客服、社媒、Slack、Discord 里，用中文快速写出可直接发送的外语内容。

---

## ✨ 特性

- **⌥ I 唤起即用**：常驻菜单栏，全局快捷键唤起/隐藏（可自定义改键）。
- **零配置即时翻译**：输入停顿 200ms 自动出译，走系统本地翻译，无需 API Key、无需联网（语言包就绪时）。
- **可选 AI 润色**：自带 DeepSeek Key 时，可对系统译文做更自然的优化，支持 **口语 / 正式 / 商务** 三种语气，流式输出。
- **本地语言包管理**：自动检测中文 → 目标语言的就绪状态，未就绪时引导准备；语言包不可用时**绝不**偷偷调用 AI（避免隐私/费用意外）。
- **常驻最前不打扰**：非激活浮窗，切到其他应用仍固定最前，且不抢走当前应用的输入焦点；可拖拽、记忆位置、输入/译文框高度可拖拽调节。
- **历史与收藏**：自动保留最近翻译；可手动 ★ 收藏常用句（最多 3 条，置顶固定不淘汰），点击任意条目回填重译。
- **克制的输出**：一键复制 / ⌘C（有选区复制选区、无选区复制全文）；不自动粘贴、不替换选中文本。
- **隐私优先**：默认翻译完全在本机系统能力内完成、不出网；DeepSeek Key 仅存 macOS Keychain，配置文件无明文。

## 🖥 运行环境

- **macOS 15.0+**（编程式 `TranslationSession` / `LanguageAvailability` 自 macOS 15 起提供）。已在 macOS 26 上构建运行。
- Apple Silicon / Intel 均可（Swift 编译为通用/本机架构）。

## 🚀 构建与运行

仅需 Swift 工具链（Xcode 或 Command Line Tools）：

```bash
git clone https://github.com/Friday-s/OptionNow.git
cd OptionNow
./build.sh release            # 编译并组装签名后的 .app
open "dist/Option Now.app"    # 启动；菜单栏出现图标，按 ⌥ I 唤起
```

> 当前为本地 ad-hoc 签名，仅供自用/构建。若要分发给他人，需用 Developer ID 证书签名并做公证（notarization），否则对方打开会被 Gatekeeper 拦截。

也可在 [Releases](https://github.com/Friday-s/OptionNow/releases) 下载已打包的 `.app`。

## ⚙️ 使用

1. 按 **⌥ I** 唤起浮窗（再按一次或 Esc 隐藏）。
2. 选择目标语言（英/日/葡/西/韩/法/德，实际可用以系统语言包为准）。
3. 用中文输入，停顿即出译文 → 点「复制」或 ⌘C 取走。
4. 需要更自然的表达：在「设置」填入 DeepSeek API Key，点「↵ AI 生成」按所选语气润色。

### AI 润色（可选）

- 在设置页填入 **DeepSeek API Key**（存入 Keychain）。
- 可选择模型 ID（默认 `deepseek-chat` 快速非推理；也可填 `deepseek-reasoner` 或你账号支持的其他 ID）。
- 高级：通过环境变量 `OPTIONNOW_DEEPSEEK_BASE` 可指向任意 OpenAI 兼容端点（自建/其他服务）。

## 🔒 隐私

- 默认系统翻译不连接任何自有/第三方服务器，不上传文本。
- 仅当你主动点击「AI 生成」时，当前中文与系统译文才会发送给你配置的 DeepSeek。
- 历史记录与收藏仅保存在本地，从不上传。
- API Key 仅存 macOS Keychain。

## 🧱 技术栈

Swift + SwiftUI + AppKit：`NSPanel`（非激活浮窗）· `NSStatusItem`（菜单栏）· Carbon `RegisterEventHotKey`（全局快捷键，无需辅助功能权限）· Apple **Translation** 框架（系统翻译）· `URLSession` SSE（DeepSeek 流式）· Keychain。

## 📁 项目结构

```
Sources/OptionNow/
  OptionNowApp.swift     入口（@main）
  Core/                  AppDelegate / FloatingPanel / PanelController /
                         HotKeyManager / KeychainHelper / Notifications
  Models/                AppLanguage / Tone / LocalLanguageStatus /
                         TranslationState / TranslationHistoryItem / HotKeyConfig
  Services/              SettingsStore / HistoryStore / LanguagePackService / AIOptimizeService
  ViewModels/            TranslatorViewModel（防抖 / 状态机 / 超时 / 编排）
  Views/                 TranslatorView / SettingsView / HistoryPanel /
                         HotKeyRecorder / ChineseInputView / SelectableTextView
build.sh                 构建并组装 .app
```

## 🧪 开发自测

内置两个无头测试入口（跑出货代码路径）：

```bash
BIN="$(swift build -c release --show-bin-path)/OptionNow"
"$BIN" --selftest    # Keychain / 历史 / 收藏 / 设置 / 快捷键 / 错误文案
"$BIN" --uitest      # 在真实运行时驱动浮窗 + 翻译管线 + 复制 + AI 流式（配合本地 mock）
```

`ACCEPTANCE.md` 记录了逐项功能验收与实测数据（翻译延迟、内存等）。

## 📄 License

[MIT](LICENSE)
