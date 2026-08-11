import Foundation

/// Local-only history (PRD §7.4, AC-HS-01/07). Two lists:
/// - `favorites`: user-pinned via ★, never auto-evicted, shown on top.
/// - `items`: recent auto-history, rolling, capped at 10.
/// Both persist to `UserDefaults`. Never uploaded.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let defaults = UserDefaults.standard
    private let recentKey = "translationHistory"
    private let favoritesKey = "translationFavorites"
    private let maxRecent = 10
    @Published private(set) var items: [TranslationHistoryItem] = []      // 最近（滚动）
    @Published private(set) var favorites: [TranslationHistoryItem] = []  // ★ 收藏（固定置顶）

    private init() {
        load()
    }

    func isFavorite(_ item: TranslationHistoryItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    // MARK: - Recent auto-history

    func add(_ item: TranslationHistoryItem) {
        guard SettingsStore.shared.historyEnabled else { return }
        // Don't duplicate into recent something already pinned as a favorite.
        if favorites.contains(where: { Self.isSameDraft($0, item) }) { return }
        insertRecent(item)
        persist()
    }

    /// Insert into recent with editing-session collapse. A newer version replaces the
    /// matching draft anywhere in the list, not only when it happens to be the top row.
    private func insertRecent(_ item: TranslationHistoryItem) {
        items.removeAll { Self.isSameDraft($0, item) }
        items.insert(item, at: 0)
        if items.count > maxRecent {
            items = Array(items.prefix(maxRecent))
        }
    }

    func delete(_ item: TranslationHistoryItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Clears the rolling recent list. Pinned favorites are intentionally kept.
    func clear() {
        items.removeAll()
        persist()
    }

    // MARK: - Favorites (★, pinned)

    /// Toggle a row's favorite state. Favoriting moves it from recent into the pinned
    /// list; unfavoriting moves it back to the top of recent.
    func toggleFavorite(_ item: TranslationHistoryItem) {
        if let idx = favorites.firstIndex(where: { $0.id == item.id }) {
            let fav = favorites.remove(at: idx)
            insertRecent(fav)
        } else {
            items.removeAll { $0.id == item.id || Self.isSameDraft($0, item) }
            favorites.removeAll { Self.isSameDraft($0, item) }
            favorites.append(item)
        }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        var loadedFavorites: [TranslationHistoryItem] = []
        var loadedItems: [TranslationHistoryItem] = []

        if let data = defaults.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([TranslationHistoryItem].self, from: data) {
            for item in decoded where !loadedFavorites.contains(where: { Self.isSameDraft($0, item) }) {
                loadedFavorites.append(item)
            }
        }
        if let data = defaults.data(forKey: recentKey),
           let decoded = try? JSONDecoder().decode([TranslationHistoryItem].self, from: data) {
            for item in decoded {
                guard !loadedFavorites.contains(where: { Self.isSameDraft($0, item) }),
                      !loadedItems.contains(where: { Self.isSameDraft($0, item) }) else { continue }
                loadedItems.append(item)
                if loadedItems.count == maxRecent { break }
            }
        }

        favorites = loadedFavorites
        items = loadedItems
        // Persist once so old duplicate rows are migrated away on the first launch.
        persist()
    }

    /// Treat punctuation/whitespace changes and a small localized edit as the same
    /// draft. This matches how the live translator records successive refinements of
    /// one message while keeping genuinely different short messages separate.
    private static func isSameDraft(_ lhs: TranslationHistoryItem,
                                    _ rhs: TranslationHistoryItem) -> Bool {
        guard lhs.targetLanguage == rhs.targetLanguage else { return false }

        let left = normalized(lhs.sourceText)
        let right = normalized(rhs.sourceText)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right || left.hasPrefix(right) || right.hasPrefix(left) { return true }

        let a = Array(left)
        let b = Array(right)
        let shorterCount = min(a.count, b.count)
        guard shorterCount >= 20 else { return false }

        var prefixCount = 0
        while prefixCount < shorterCount, a[prefixCount] == b[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < shorterCount - prefixCount,
              a[a.count - 1 - suffixCount] == b[b.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let covered = prefixCount + suffixCount
        if Double(covered) / Double(shorterCount) >= 0.88 { return true }

        // A user may move one clause earlier/later while refining the same message.
        // Adjacent-character overlap remains high after that move even though the
        // common prefix/suffix becomes short, so use it as the second conservative
        // signal for long drafts.
        let leftPairs = characterPairs(a)
        let rightPairs = characterPairs(b)
        guard !leftPairs.isEmpty, !rightPairs.isEmpty else { return false }
        let sharedCount = leftPairs.intersection(rightPairs).count
        let dice = Double(sharedCount * 2) / Double(leftPairs.count + rightPairs.count)
        return dice >= 0.86
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func characterPairs(_ characters: [Character]) -> Set<String> {
        guard characters.count >= 2 else { return [] }
        return Set((0..<(characters.count - 1)).map {
            String([characters[$0], characters[$0 + 1]])
        })
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: recentKey)
        }
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: favoritesKey)
        }
    }
}
