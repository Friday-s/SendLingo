import SwiftUI
import AppKit

/// Read-only, selectable text view whose ⌘C copies the **selection** when there is
/// one, and the **whole text** when there is none (FIX-1 / AC-CP-02/03).
final class CopyAwareTextView: NSTextView {
    override func copy(_ sender: Any?) {
        if selectedRange().length == 0 {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(string, forType: .string)
        } else {
            super.copy(sender)
        }
    }
}

struct SelectableTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 14
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let tv = CopyAwareTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = textColor
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? CopyAwareTextView else { return }
        if tv.string != text { tv.string = text }
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = textColor
    }
}
