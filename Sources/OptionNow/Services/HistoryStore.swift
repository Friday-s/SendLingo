import Foundation

/// Local-only history (PRD §7.4, AC-HS-01/07). Two lists:
/// - `favorites`: user-pinned via ★, capped at 3, never auto-evicted, shown on top.
/// - `items`: recent auto-history, rolling, capped at 10.
/// Both persist to `UserDefaults`. Never uploaded.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let defaults = UserDefaults.standard
    private let recentKey = "translationHistory"
    private let favoritesKey = "translationFavorites"
    private let maxRecent = 10
    let maxFavorites = 3

    @Published private(set) var items: [TranslationHistoryItem] = []      // 最近（滚动）
    @Published private(set) var favorites: [TranslationHistoryItem] = []  // ★ 收藏（最多3，固定）

    private init() {
        load()
    }

    var canAddFavorite: Bool { favorites.count < maxFavorites }

    func isFavorite(_ item: TranslationHistoryItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    // MARK: - Recent auto-history

    func add(_ item: TranslationHistoryItem) {
        guard SettingsStore.shared.historyEnabled else { return }
        // Don't duplicate into recent something already pinned as a favorite.
        if favorites.contains(where: {
            $0.targetLanguage == item.targetLanguage && $0.sourceText == item.sourceText
        }) { return }
        insertRecent(item)
        persist()
    }

    /// Insert into recent with editing-session collapse (你 → 你好 → 你好吗 replaces the
    /// top entry instead of duplicating) and the rolling cap.
    private func insertRecent(_ item: TranslationHistoryItem) {
        if let first = items.first,
           first.targetLanguage == item.targetLanguage,
           (item.sourceText.hasPrefix(first.sourceText) || first.sourceText.hasPrefix(item.sourceText)) {
            items[0] = item
        } else {
            items.insert(item, at: 0)
        }
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

    // MARK: - Favorites (★, pinned, max 3)

    /// Toggle a row's favorite state. Favoriting moves it from recent into the pinned
    /// list (max 3); unfavoriting moves it back to the top of recent.
    func toggleFavorite(_ item: TranslationHistoryItem) {
        if let idx = favorites.firstIndex(where: { $0.id == item.id }) {
            let fav = favorites.remove(at: idx)
            insertRecent(fav)
        } else {
            guard canAddFavorite else { return } // 最多 3 条
            items.removeAll { $0.id == item.id }
            favorites.append(item)
        }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: recentKey),
           let decoded = try? JSONDecoder().decode([TranslationHistoryItem].self, from: data) {
            items = Array(decoded.prefix(maxRecent))
        }
        if let data = defaults.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([TranslationHistoryItem].self, from: data) {
            favorites = Array(decoded.prefix(maxFavorites))
        }
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
