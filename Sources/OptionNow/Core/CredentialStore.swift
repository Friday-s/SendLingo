import Foundation

/// Stores the DeepSeek API key on disk under Application Support so it **persists
/// across app rebuilds/updates**.
///
/// Why not Keychain: the app is ad-hoc signed, and its signature changes on every
/// rebuild. Keychain ties a generic-password item's access to the creating signature,
/// so a freshly-built binary can no longer read the previously-saved key — it looks
/// "lost" after every update. A per-user file keyed by a stable path avoids that.
///
/// Trade-off: the key is stored as plaintext in the user's home (file mode 0600, only
/// the user can read it) rather than encrypted in Keychain. For a personal, revocable
/// DeepSeek key this is an acceptable convenience trade-off. (A stable code-signing
/// identity would let us move back to Keychain without losing persistence.)
enum CredentialStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OptionNow", isDirectory: true)
    }
    private static var fileURL: URL { directory.appendingPathComponent("deepseek.key") }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(trimmed.utf8).write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    static func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func delete() -> Bool {
        try? FileManager.default.removeItem(at: fileURL)
        return true
    }

    static var hasKey: Bool { load() != nil }
}
