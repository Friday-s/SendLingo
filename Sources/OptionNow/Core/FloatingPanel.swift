import AppKit

/// A non-activating, always-on-top panel that hosts the translator UI.
///
/// - Stays in front when the user switches to other apps (AC-WIN-01).
/// - Does **not** activate the owning app / steal focus from the frontmost app,
///   yet can still become key so its text field accepts input (AC-WIN-02).
/// - Draggable by background (AC-WIN-03); Esc hides it (AC-HK-04 / AC-WIN-08).
final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        // Borderless: no title bar at all — removes the stray titlebar strip / white
        // separator line. The visible rounded card is drawn by the SwiftUI content.
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        // Visible on every Space and above full-screen apps (AC-WIN-01 / AC-WIN-06).
        // Note: .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    // Must become key so the text field receives keystrokes...
    override var canBecomeKey: Bool { true }
    // ...but never main, so the owning (accessory) app is not activated.
    override var canBecomeMain: Bool { false }

    /// Esc → hide (handled here so it works regardless of inner focus).
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
