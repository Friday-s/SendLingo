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
            let keyCode = event.keyCode
            let hasOption = event.modifierFlags.contains(.option)
            let hasCommand = event.modifierFlags.contains(.command)
            let isReturn = (keyCode == 36 || keyCode == 76) // Return / numpad Enter
            let isC = (keyCode == 8)                          // 'C'

            // ⌥↵ → AI optimization.
            if isReturn && hasOption {
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let panel = self.panel, panel.isKeyWindow else { return false }
                    self.viewModel.requestAI()
                    return true
                }
                return handled ? nil : event // consume so it doesn't insert a newline
            }

            // ⌘C with no active text selection → copy the current translation result.
            // (With a selection, fall through so the selected text copies normally.)
            if isC && hasCommand && !hasOption {
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let panel = self.panel, panel.isKeyWindow else { return false }
                    if let tv = panel.firstResponder as? NSTextView, tv.selectedRange().length > 0 {
                        return false // let the selection copy
                    }
                    return self.viewModel.copyResultToPasteboard()
                }
                if handled { return nil }
            }

            return event
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
        // Keep the remembered SIZE, but always launch at the mouse cursor (anchor C:
        // the cursor lands on the input field), instead of the last position.
        var frame = panel.frame
        if let savedSize = settings.loadWindowFrame()?.size { frame.size = savedSize }
        frame.size.width = max(frame.size.width, panel.contentMinSize.width)
        frame.size.height = max(frame.size.height, panel.contentMinSize.height)
        frame.origin = cursorAnchoredOrigin(for: frame.size)
        panel.setFrame(frame, display: false)

        // The user explicitly invoked SendLingo to type. A newly renamed accessory
        // app can own a visually focused non-activating panel while still not being
        // the active application, so macOS continues sending keyboard events to the
        // previous app. Activate first, then make the panel key.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Ask the SwiftUI view to focus the input field (AC-HK-01).
        viewModel.requestFocus()
        // Activation completes asynchronously. Reassert key/first-responder state on
        // the next main-loop turn so the first keystroke is never lost.
        DispatchQueue.main.async { [weak self, weak panel] in
            panel?.makeKey()
            self?.viewModel.requestFocus()
        }
    }

    /// Origin that places the panel so the mouse cursor falls on the input field
    /// (anchor C), clamped to the visible area of the screen under the cursor.
    private func cursorAnchoredOrigin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        // Offset from the window's top-left to the anchor point (inside the input box).
        let anchorX: CGFloat = 50
        let anchorY: CGFloat = 64
        // Cocoa coords have a bottom-left origin; window origin is its bottom-left.
        var origin = NSPoint(x: mouse.x - anchorX, y: mouse.y - size.height + anchorY)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), max(vf.minX, vf.maxX - size.width))
            origin.y = min(max(origin.y, vf.minY), max(vf.minY, vf.maxY - size.height))
        }
        return origin
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
        panel.contentMinSize = NSSize(width: 340, height: 360)

        let root = TranslatorView()
            .environmentObject(viewModel)
            .environmentObject(settings)
            .environmentObject(HistoryStore.shared)
            .environmentObject(LanguagePackService.shared)

        // Pin the SwiftUI host to a resizable AppKit container. Assigning a hosting
        // view with translatesAutoresizingMaskIntoConstraints=false directly as the
        // contentView leaves it without constraints, so the window frame can resize
        // while the page remains at its original size.
        let container = NSView(frame: panel.contentLayoutRect)
        container.autoresizingMask = [.width, .height]
        panel.contentView = container

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.onEscape = { [weak self] in self?.hide() }
        panel.onResignKey = { [weak self] in
            guard let self else { return }
            if self.settings.autoHideOnBlur { self.hide() }
        }

        // Persist the frame on drag and resize so the SIZE is remembered across
        // sessions (the launch position now follows the cursor, not this frame).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let p = self.panel else { return }
                    self.settings.saveWindowFrame(p.frame)
                }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let p = self.panel else { return }
                    self.settings.saveWindowFrame(p.frame)
                }
        }

        self.panel = panel
        return panel
    }
}
