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
    var minimumHeight: CGFloat = 40
    /// When this changes, the view grabs focus and selects all (so ⌘A/⌘C copy it).
    var focusToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(focusToken) }
    final class Coordinator { var lastFocusToken: Int; init(_ t: Int) { lastFocusToken = t } }

    func makeNSView(context: Context) -> CopyAwareTextView {
        let tv = CopyAwareTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.font = NSFont.systemFont(ofSize: fontSize)
        tv.textColor = textColor
        tv.string = text
        return tv
    }

    func updateNSView(_ tv: CopyAwareTextView, context: Context) {
        if tv.string != text { tv.string = text }
        if tv.font?.pointSize != fontSize { tv.font = NSFont.systemFont(ofSize: fontSize) }
        if tv.textColor != textColor { tv.textColor = textColor }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.selectAll(nil)
            }
        }
    }

    /// Let each result grow to its wrapped text height. The surrounding translation
    /// ScrollView then owns scrolling for the whole result instead of nesting a tiny
    /// independent scroller inside every system/AI/back-translation section.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView tv: CopyAwareTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let textContainer = tv.textContainer,
              let layoutManager = tv.layoutManager else { return nil }

        tv.setFrameSize(NSSize(width: width, height: max(tv.frame.height, minimumHeight)))
        let textWidth = max(1, width - tv.textContainerInset.width * 2)
        textContainer.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let height = ceil(usedHeight + tv.textContainerInset.height * 2)
        return CGSize(width: width, height: max(minimumHeight, height))
    }
}
