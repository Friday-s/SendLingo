import AppKit

/// Entry point. A plain AppKit lifecycle (rather than a SwiftUI `App` scene) gives
/// full control over the accessory activation policy, the non-activating panel,
/// and the Carbon global hotkey.
@main
@MainActor
enum OptionNowMain {
    // Held strongly so the delegate outlives `main()`.
    static var delegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
