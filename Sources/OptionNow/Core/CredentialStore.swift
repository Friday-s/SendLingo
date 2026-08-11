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
@MainActor
enum CredentialStore {
    /// In-memory cache of the on-disk key. `nil` = not read yet; `.some(nil)` = known
    /// absent. `hasKey` is evaluated inside SwiftUI view bodies, so without this every
    /// render would hit the filesystem.
    private static var cachedKey: String??

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SendLingo", isDirectory: true)
    }
    private static var fileURL: URL { directory.appendingPathComponent("deepseek.key") }
    private static var legacyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OptionNow", isDirectory: true)
            .appendingPathComponent("deepseek.key")
    }
    private static var migrationMarkerURL: URL {
        directory.appendingPathComponent(".migrated-from-optionnow")
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(trimmed.utf8).write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            cachedKey = .some(trimmed)
            return true
        } catch {
            return false
        }
    }

    static func load() -> String? {
        if let cached = cachedKey { return cached }
        migrateLegacyKeyIfNeeded()
        let value: String?
        if let data = try? Data(contentsOf: fileURL),
           let s = String(data: data, encoding: .utf8) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            value = trimmed.isEmpty ? nil : trimmed
        } else {
            value = nil
        }
        cachedKey = .some(value)
        return value
    }

    @discardableResult
    static func delete() -> Bool {
        try? FileManager.default.removeItem(at: fileURL)
        cachedKey = .some(nil)
        return true
    }

    static var hasKey: Bool { load() != nil }

    /// Copy the legacy key once, leaving the old file untouched as a rollback copy.
    /// The marker prevents a later user deletion in SendLingo from importing it again.
    private static func migrateLegacyKeyIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: migrationMarkerURL.path) else { return }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: fileURL.path),
               fm.fileExists(atPath: legacyFileURL.path) {
                try fm.copyItem(at: legacyFileURL, to: fileURL)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            try Data().write(to: migrationMarkerURL, options: [.atomic])
        } catch {
            // Retry on the next read. Normal no-key use remains available.
        }
    }
}
