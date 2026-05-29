import SwiftUI
import AppKit

/// Editable multi-line input backed by an `NSTextView`, with the placeholder drawn
/// inside the text view at the exact text origin (so it aligns perfectly with typed
/// text — fixes the misaligned placeholder). Standard editing shortcuts (⌘A/C/V/X/Z)
/// work via the app's Edit menu. Focus follows `focusToken`.
final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        placeholder.draw(at: origin, withAttributes: attrs)
    }
}

struct ChineseInputView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var placeholder: String
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let tv = PlaceholderTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = .labelColor
        tv.placeholder = placeholder
        // Explicit, predictable text origin so the placeholder aligns exactly.
        tv.textContainerInset = NSSize(width: 5, height: 6)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PlaceholderTextView else { return }
        if tv.string != text { tv.string = text; tv.needsDisplay = true }
        if tv.font?.pointSize != fontSize { tv.font = NSFont.systemFont(ofSize: fontSize) }
        tv.placeholder = placeholder

        // Focus the input when asked (panel shown / hotkey wake).
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChineseInputView
        weak var textView: NSTextView?
        var lastFocusToken: Int

        init(_ parent: ChineseInputView) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            (tv as? PlaceholderTextView)?.needsDisplay = true
        }
    }
}
