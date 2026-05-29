import Foundation

/// A target language that Option Now can translate Chinese into.
///
/// The source language is always Simplified Chinese (`zh-Hans`) — Option Now is a
/// one-directional "write Chinese, send foreign language" tool (PRD §0, AC-TR-10).
struct AppLanguage: Identifiable, Hashable, Codable {
    /// BCP-47 identifier passed to `Locale.Language` / Translation framework.
    let code: String
    /// Display name shown in the picker.
    let displayName: String

    var id: String { code }

    /// The fixed source language for the whole product.
    static let source = AppLanguage(code: "zh-Hans", displayName: "中文（简体）")

    /// First batch of target languages (PRD §7.1.1). Actual availability is
    /// resolved at runtime against the system Translation framework.
    static let firstBatch: [AppLanguage] = [
        AppLanguage(code: "en",    displayName: "英语 English"),
        AppLanguage(code: "ja",    displayName: "日语 日本語"),
        AppLanguage(code: "pt",    displayName: "葡萄牙语 Português"),
        AppLanguage(code: "es",    displayName: "西班牙语 Español"),
        AppLanguage(code: "ko",    displayName: "韩语 한국어"),
        AppLanguage(code: "fr",    displayName: "法语 Français"),
        AppLanguage(code: "de",    displayName: "德语 Deutsch")
    ]

    static func named(_ code: String) -> AppLanguage {
        firstBatch.first { $0.code == code } ?? firstBatch[0]
    }
}
