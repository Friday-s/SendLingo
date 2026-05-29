import Foundation
import Translation

/// Wraps the system `LanguageAvailability` to report local language-pack status
/// for `zh-Hans -> target` pairs (PRD §7.2, AC-LP-01). Results are cached to avoid
/// frequent re-checks (§13.3).
@MainActor
final class LanguagePackService: ObservableObject {
    static let shared = LanguagePackService()

    private let sourceLanguage = Locale.Language(identifier: AppLanguage.source.code)

    /// Cached status per target code, plus the time it was checked.
    @Published private(set) var statuses: [String: LocalLanguageStatus] = [:]
    private var checkedAt: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 60

    private init() {}

    func cachedStatus(for code: String) -> LocalLanguageStatus {
        statuses[code] ?? .unknown
    }

    /// Refresh the status for one target language (uses cache within TTL unless forced).
    @discardableResult
    func refresh(_ code: String, force: Bool = false) async -> LocalLanguageStatus {
        if !force, let at = checkedAt[code], Date().timeIntervalSince(at) < cacheTTL,
           let cached = statuses[code] {
            return cached
        }
        let target = Locale.Language(identifier: code)
        // Instantiate per call so the (main-actor) service never sends a stored
        // availability object across actors (Swift 6 strict concurrency).
        let availability = LanguageAvailability()
        let raw = await availability.status(from: sourceLanguage, to: target)
        let mapped = Self.map(raw)
        statuses[code] = mapped
        checkedAt[code] = Date()
        return mapped
    }

    /// Refresh all first-batch languages (called at launch and on the settings page).
    func refreshAll() async {
        for lang in AppLanguage.firstBatch {
            await refresh(lang.code, force: true)
        }
    }

    /// Mark a pair installed after a successful `prepareTranslation()` (AC-LP-05).
    func markInstalled(_ code: String) {
        statuses[code] = .installed
        checkedAt[code] = Date()
    }

    func markPreparing(_ code: String) {
        statuses[code] = .preparing
    }

    private static func map(_ status: LanguageAvailability.Status) -> LocalLanguageStatus {
        switch status {
        case .installed:   return .installed
        case .supported:   return .supportedButNotInstalled
        case .unsupported: return .unsupported
        @unknown default:  return .unknown
        }
    }
}
