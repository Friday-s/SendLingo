import SwiftUI
import AppKit

/// A native resize handle for the input/translation divider.
///
/// It overrides `mouseDownCanMoveWindow` to return `false` so that — unlike a plain
/// SwiftUI `Divider` on a `isMovableByWindowBackground` window — pressing it does NOT
/// start a window move. It tracks the mouse itself and reports the drag delta
/// (downward-positive, since the input pane sits on top), like `NSSplitView`'s divider.
final class ResizeHandleNSView: NSView {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?
    private var startY: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let lineH: CGFloat = 1
        NSRect(x: 0, y: (bounds.height - lineH) / 2, width: bounds.width, height: lineH).fill()
    }

    override func mouseDown(with event: NSEvent) {
        startY = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        // Window coords have a bottom-left origin (y up); dragging DOWN lowers y, and
        // should grow the (top) input pane → delta = start − current.
        onChanged?(startY - event.locationInWindow.y)
    }

    override func mouseUp(with event: NSEvent) {
        onEnded?()
    }
}

struct SplitHandle: NSViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> ResizeHandleNSView {
        let v = ResizeHandleNSView()
        v.onChanged = onChanged
        v.onEnded = onEnded
        return v
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }
}
