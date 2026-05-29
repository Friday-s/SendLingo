import Foundation
import SwiftUI

/// Theme option (P1, AC-ST-07).
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// User settings, persisted to `UserDefaults`. Holds **no** API key — that lives
/// only in the Keychain (AC-SEC-01). All access is on the main actor.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let defaultTargetLanguage = "defaultTargetLanguage"
        static let defaultTone = "defaultTone"
        static let hotkey = "hotkey"
        static let aiEnabled = "aiEnabled"
        static let deepseekModel = "deepseekModel"
        static let historyEnabled = "historyEnabled"
        static let debounceMs = "debounceMs"
        static let autoHideOnBlur = "autoHideOnBlur"
        static let theme = "theme"
        static let fontSize = "fontSize"
        static let windowFrame = "windowFrame"
    }

    @Published var defaultTargetLanguage: String { didSet { defaults.set(defaultTargetLanguage, forKey: Key.defaultTargetLanguage) } }
    @Published var defaultTone: Tone { didSet { defaults.set(defaultTone.rawValue, forKey: Key.defaultTone) } }
    @Published var hotkey: HotKeyConfig { didSet { persistHotkey() } }
    /// `aiEnabled` only controls whether the AI entry is *shown* (FIX-3). System
    /// translation never depends on it.
    @Published var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled) } }
    /// DeepSeek model id used for AI optimization (user-selectable, AC-AI / P1 provider seam).
    @Published var deepseekModel: String { didSet { defaults.set(deepseekModel, forKey: Key.deepseekModel) } }
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) } }
    @Published var debounceMs: Int { didSet { defaults.set(debounceMs, forKey: Key.debounceMs) } }
    @Published var autoHideOnBlur: Bool { didSet { defaults.set(autoHideOnBlur, forKey: Key.autoHideOnBlur) } }
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }

    /// True when the global hotkey could not be registered (taken by the system /
    /// another app). Not persisted — recomputed on every (re)registration (AC-HK-07).
    @Published var hotkeyConflict: Bool = false

    private init() {
        // Defaults reflect the acceptance fixes:
        // - default tone = casual (FIX-4 / AC-AI-05)
        // - aiEnabled = true means "show entry"; gated by Keychain key (FIX-3)
        // - debounce = 200ms
        self.defaultTargetLanguage = defaults.string(forKey: Key.defaultTargetLanguage) ?? "en"
        self.defaultTone = Tone(rawValue: defaults.string(forKey: Key.defaultTone) ?? "") ?? .casual
        self.aiEnabled = defaults.object(forKey: Key.aiEnabled) as? Bool ?? true
        self.deepseekModel = defaults.string(forKey: Key.deepseekModel) ?? "deepseek-chat"
        self.historyEnabled = defaults.object(forKey: Key.historyEnabled) as? Bool ?? true
        self.debounceMs = defaults.object(forKey: Key.debounceMs) as? Int ?? 200
        self.autoHideOnBlur = defaults.object(forKey: Key.autoHideOnBlur) as? Bool ?? false
        self.theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        self.fontSize = defaults.object(forKey: Key.fontSize) as? Double ?? 14.0

        if let data = defaults.data(forKey: Key.hotkey),
           let hk = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            self.hotkey = hk
        } else {
            self.hotkey = .defaultHotKey
        }
    }

    private func persistHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    // MARK: - Window frame memory (AC-WIN-04)

    func saveWindowFrame(_ frame: CGRect) {
        let dict: [String: CGFloat] = [
            "x": frame.origin.x, "y": frame.origin.y,
            "width": frame.size.width, "height": frame.size.height
        ]
        defaults.set(dict, forKey: Key.windowFrame)
    }

    func loadWindowFrame() -> CGRect? {
        guard let dict = defaults.dictionary(forKey: Key.windowFrame) as? [String: CGFloat],
              let x = dict["x"], let y = dict["y"],
              let w = dict["width"], let h = dict["height"], w > 0, h > 0 else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
