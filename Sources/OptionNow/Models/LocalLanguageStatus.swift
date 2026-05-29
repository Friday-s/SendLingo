import Foundation

/// Local language-pack readiness for a `zh-Hans -> target` pair (PRD §2.4 / §13.3, AC-LP-01).
enum LocalLanguageStatus: Equatable {
    /// Local translation is ready; can translate instantly with no download.
    case installed
    /// System supports the pair but the language pack is not prepared yet.
    case supportedButNotInstalled
    /// System is downloading / preparing the language pack.
    case preparing
    /// Current macOS Translation framework does not support this pair.
    case unsupported
    /// Current macOS version cannot do programmatic translation at all.
    case systemUnavailable
    /// Not yet checked.
    case unknown

    var shortLabel: String {
        switch self {
        case .installed:                return "已就绪"
        case .supportedButNotInstalled: return "需准备"
        case .preparing:                return "准备中"
        case .unsupported:              return "暂不支持"
        case .systemUnavailable:        return "系统版本不支持"
        case .unknown:                  return "检查中"
        }
    }

    /// Whether the language can be selected in the picker (AC-LP-08).
    var isSelectable: Bool {
        switch self {
        case .unsupported, .systemUnavailable: return false
        default: return true
        }
    }
}
