import Foundation
import Security

/// Stores the DeepSeek API key in the macOS Keychain (AC-SEC-01 / AC-ST-01).
/// The key is **never** written to UserDefaults / config files in plaintext.
enum KeychainHelper {
    private static let service = "com.optionnow.app"
    private static let account = "deepseek-api-key"

    @discardableResult
    static func save(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        // Remove any existing item first, then add a fresh one.
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var hasKey: Bool {
        guard let k = load() else { return false }
        return !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
