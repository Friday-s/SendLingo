import Foundation
import Carbon.HIToolbox

/// A global hotkey definition: a virtual key code plus Carbon modifier flags.
struct HotKeyConfig: Codable, Equatable {
    /// `kVK_*` virtual key code.
    var keyCode: UInt32
    /// Carbon modifier mask (`optionKey`, `cmdKey`, `controlKey`, `shiftKey`).
    var carbonModifiers: UInt32

    /// Default: ⌥ I (PRD §0, AC-HK-01). `kVK_ANSI_I` = 34.
    static let defaultHotKey = HotKeyConfig(keyCode: UInt32(kVK_ANSI_I),
                                            carbonModifiers: UInt32(optionKey))

    /// Human-readable representation, e.g. "⌥ I".
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        if !s.isEmpty { s += " " }
        s += HotKeyConfig.keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: UInt32) -> String {
        // Common letter / number keys; fall back to a generic label.
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋"
        ]
        return map[Int(keyCode)] ?? "Key#\(keyCode)"
    }

    /// Translate a Cocoa `NSEvent.modifierFlags`-style mask into Carbon modifiers.
    static func carbonModifiers(fromCocoa cocoaRawValue: UInt) -> UInt32 {
        var carbon: UInt32 = 0
        // NSEvent.ModifierFlags raw values.
        let control: UInt = 0x40000
        let option:  UInt = 0x80000
        let shift:   UInt = 0x20000
        let command: UInt = 0x100000
        if cocoaRawValue & control != 0 { carbon |= UInt32(controlKey) }
        if cocoaRawValue & option  != 0 { carbon |= UInt32(optionKey) }
        if cocoaRawValue & shift   != 0 { carbon |= UInt32(shiftKey) }
        if cocoaRawValue & command != 0 { carbon |= UInt32(cmdKey) }
        return carbon
    }
}
