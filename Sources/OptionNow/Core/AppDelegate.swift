import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore.shared
    private lazy var viewModel = TranslatorViewModel()
    private lazy var panelController = PanelController(viewModel: viewModel, settings: settings)

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var hotkeyCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, never steals focus on launch (PRD §7.5).
        NSApp.setActivationPolicy(.accessory)

        setupMainMenu()
        setupStatusItem()
        registerHotKey()

        // Re-register whenever the user changes the hotkey in Settings (AC-HK-06).
        hotkeyCancellable = settings.$hotkey
            .dropFirst()
            .sink { [weak self] _ in self?.registerHotKey() }

        // Open settings when the panel UI requests it.
        NotificationCenter.default.addObserver(
            forName: .optionNowOpenSettings, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.openSettings() }
        }

        // Prime language-pack statuses for the picker (AC-LP-01).
        Task { await LanguagePackService.shared.refreshAll() }

        // Debug aid: auto-show the panel on launch (for screenshots / smoke tests).
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.panelController.show()
            }
        }

        // In-process integration tests against the live runtime.
        if CommandLine.arguments.contains("--uitest") {
            Task { @MainActor in
                let code = await UITests.run(panelController: panelController,
                                             vm: viewModel,
                                             settings: settings)
                exit(code)
            }
        }
    }

    // MARK: - Main menu (enables ⌘A/⌘C/⌘V/⌘X/⌘Z in all text fields)

    /// An accessory (LSUIElement) app has no menu bar by default, so macOS won't route
    /// the standard editing key-equivalents. Installing an Edit menu makes select-all /
    /// copy / paste / cut / undo work in the input box, the 译文 area, and the API-key
    /// field (addresses the "can't paste / can't ⌘A" feedback).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (Quit).
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Option Now", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu (standard responder-chain selectors).
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu bar (AC-WIN-07)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Brand-matching ⌥ glyph; fall back if the SF Symbol is unavailable.
            let image = NSImage(systemSymbolName: "option", accessibilityDescription: "Option Now")
                ?? NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Option Now")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 Option Now", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Option Now", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openPanel() { panelController.show() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Hotkey

    private func registerHotKey() {
        let ok = HotKeyManager.shared.register(settings.hotkey) { [weak self] in
            self?.panelController.toggle()
        }
        settings.hotkeyConflict = !ok
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let root = SettingsView()
                .environmentObject(settings)
                .environmentObject(HistoryStore.shared)
                .environmentObject(LanguagePackService.shared)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Option Now 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 460, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
