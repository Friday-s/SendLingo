import AppKit
import SwiftUI

/// Owns the floating panel and its SwiftUI content, plus show/hide/toggle and
/// window-position memory (AC-WIN-04). Keeps the panel alive across hides so the
/// SwiftUI state (input, history) persists; only orders it out.
@MainActor
final class PanelController: NSObject {
    private(set) var panel: FloatingPanel?
    private let viewModel: TranslatorViewModel
    private let settings: SettingsStore
    private var keyMonitor: Any?

    init(viewModel: TranslatorViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
        super.init()
        NotificationCenter.default.addObserver(
            forName: .optionNowHide, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
        }
        // ⌥↵ (Option+Return) → trigger AI optimization. A local monitor catches it
        // before the focused text view turns it into a newline, and works regardless
        // of which field has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Read value-type fields out here (NSEvent isn't Sendable, so it can't cross
            // into the @MainActor closure below).
            let isReturn = (event.keyCode == 36 || event.keyCode == 76) // Return / numpad Enter
            let hasOption = event.modifierFlags.contains(.option)
            guard isReturn && hasOption else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, panel.isKeyWindow else { return false }
                self.viewModel.requestAI()
                return true
            }
            return handled ? nil : event // consume so it doesn't insert a newline
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        if let frame = settings.loadWindowFrame() {
            panel.setFrame(frame, display: false)
            ensureOnScreen(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        // Ask the SwiftUI view to focus the input field (AC-HK-01).
        viewModel.requestFocus()
    }

    func hide() {
        guard let panel else { return }
        settings.saveWindowFrame(panel.frame)
        panel.orderOut(nil)
    }

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }

        let defaultFrame = settings.loadWindowFrame()
            ?? NSRect(x: 0, y: 0, width: 420, height: 560)
        let panel = FloatingPanel(contentRect: defaultFrame)

        let root = TranslatorView()
            .environmentObject(viewModel)
            .environmentObject(settings)
            .environmentObject(HistoryStore.shared)
            .environmentObject(LanguagePackService.shared)

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting

        panel.onEscape = { [weak self] in self?.hide() }
        panel.onResignKey = { [weak self] in
            guard let self else { return }
            if self.settings.autoHideOnBlur { self.hide() }
        }

        // Persist position whenever the user drags the window (AC-WIN-03/04).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let p = self.panel else { return }
                    self.settings.saveWindowFrame(p.frame)
                }
        }

        if settings.loadWindowFrame() == nil {
            panel.center()
        }
        self.panel = panel
        return panel
    }

    /// Nudge the panel back on-screen if a saved frame is off the current displays
    /// (e.g. a monitor was unplugged) — AC-WIN-05.
    private func ensureOnScreen(_ panel: NSPanel) {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !visible { panel.center() }
    }
}
