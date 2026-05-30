import SwiftUI
import AppKit

/// Editable multi-line input backed by an `NSTextView`, with the placeholder drawn
/// inside the text view at the exact text origin (so it aligns perfectly with typed
/// text — fixes the misaligned placeholder). Standard editing shortcuts (⌘A/C/V/X/Z)
/// work via the app's Edit menu. Focus follows `focusToken`.
final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""
    /// Provides the current translation result; `onCopyResult` fires after copying it.
    var resultProvider: (() -> String)?
    var onCopyResult: (() -> Void)?

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

    /// ⌘C with no selection in the input → copy the current translation result
    /// (so the user can type then just press ⌘C). With a selection → copy that text.
    override func copy(_ sender: Any?) {
        if selectedRange().length == 0, let result = resultProvider?(), !result.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(result, forType: .string)
            onCopyResult?()
        } else {
            super.copy(sender)
        }
    }

    /// NSTextView disables the Copy command when nothing is selected, which would
    /// swallow ⌘C. Keep it enabled whenever there is a translation result to copy, so
    /// ⌘C (no selection) reaches `copy(_:)` above and copies the result.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)), selectedRange().length == 0 {
            return !((resultProvider?() ?? "").isEmpty)
        }
        return super.validateUserInterfaceItem(item)
    }

    /// Most reliable interception: the key window's first responder gets
    /// `performKeyEquivalent` *before* the app's Edit menu. So ⌘C with no selection
    /// copies the translation result here, ahead of any menu / IME handling.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           event.charactersIgnoringModifiers == "c",
           selectedRange().length == 0,
           let result = resultProvider?(), !result.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(result, forType: .string)
            onCopyResult?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ChineseInputView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var placeholder: String
    var focusToken: Int
    /// Bumped only on external changes (history refill / char-limit trim). The field
    /// is re-synced from `text` only when this changes — never on normal typing.
    var resetToken: Int = 0
    var resultProvider: () -> String = { "" }
    var onCopyResult: () -> Void = {}

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
        tv.resultProvider = resultProvider
        tv.onCopyResult = onCopyResult
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? PlaceholderTextView else { return }
        if tv.font?.pointSize != fontSize { tv.font = NSFont.systemFont(ofSize: fontSize) }
        tv.placeholder = placeholder
        tv.resultProvider = resultProvider
        tv.onCopyResult = onCopyResult

        // Re-sync the field ONLY on an external change (token bump). Never overwrite
        // on normal typing — that round-trip dropped characters when typing fast.
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            if tv.string != text {
                tv.string = text
                tv.needsDisplay = true
            }
        }

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
        var lastResetToken: Int

        init(_ parent: ChineseInputView) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken
            self.lastResetToken = parent.resetToken
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            (tv as? PlaceholderTextView)?.needsDisplay = true
        }
    }
}
