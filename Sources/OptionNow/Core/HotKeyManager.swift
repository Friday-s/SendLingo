import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon `RegisterEventHotKey`.
///
/// Carbon hotkeys do **not** require Accessibility permission (AC-SEC-05) and only
/// intercept the exact registered combination, leaving normal text input in other
/// apps untouched (AC-HK-05). Registration failure is reported so the UI can prompt
/// the user to pick another key (AC-HK-07).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    fileprivate var onTrigger: (() -> Void)?
    private let signature: OSType = 0x4F50544E // 'OPTN'

    private init() {}

    /// Register (or re-register) the hotkey. Returns false if the OS rejects it
    /// (e.g. already taken by the system or another app).
    @discardableResult
    func register(_ config: HotKeyConfig, onTrigger: @escaping () -> Void) -> Bool {
        unregister()
        self.onTrigger = onTrigger

        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: OSType(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(),
                                hotKeyEventCallback,
                                1, &eventType, selfPtr, &eventHandler)
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(config.keyCode,
                                         config.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        return status == noErr && hotKeyRef != nil
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

/// C callback for the Carbon hotkey event. Carbon dispatches this on the main run
/// loop, so it is safe to assume main-actor isolation.
private func hotKeyEventCallback(_ handler: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.onTrigger?()
    }
    return noErr
}
