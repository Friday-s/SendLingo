import SwiftUI
import AppKit

/// Records a new global hotkey: click to arm, then press a modifier+key combo
/// (AC-HK-06). A bare key with no modifier is ignored to avoid hijacking plain typing.
struct HotKeyRecorder: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "请按下快捷键…" : settings.hotkey.displayString)
                .frame(minWidth: 110)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording without changing the key.
            if event.keyCode == 53 { stop(); return nil }

            let cocoaMods = event.modifierFlags
                .intersection([.command, .option, .control, .shift]).rawValue
            let carbon = HotKeyConfig.carbonModifiers(fromCocoa: cocoaMods)
            guard carbon != 0 else { return nil } // need at least one modifier; keep listening

            settings.hotkey = HotKeyConfig(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            stop()
            return nil // consume
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}
