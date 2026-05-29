import Foundation

/// Error surfaced by the translation pipeline (system + AI), mapped to user-facing copy.
enum TranslationError: Error, Equatable {
    // System translation
    case languageNotInstalled
    case unsupported
    case systemVersionUnsupported
    case translationSlowTimeout   // FIX-5 / AC-TR-07
    case systemTranslationFailed(String)

    // AI optimization (DeepSeek)
    case missingKey
    case invalidKey
    case rateLimited
    case timeout
    case networkError
    case providerError(String)

    var userMessage: String {
        switch self {
        case .languageNotInstalled:    return "需要先准备该目标语言的本地语言包"
        case .unsupported:             return "当前系统暂不支持中文到该语言"
        case .systemVersionUnsupported:return "当前 macOS 版本不支持编程式系统翻译"
        case .translationSlowTimeout:  return "翻译较慢，请重试或缩短文本"
        case .systemTranslationFailed: return "翻译失败，请重试"
        case .missingKey:              return "填写 DeepSeek API Key 后可使用 AI 优化"
        case .invalidKey:              return "API Key 无效，请检查后重试"
        case .rateLimited:             return "AI 优化失败（请求过于频繁），可稍后重试"
        case .timeout:                 return "AI 优化超时，可稍后重试"
        case .networkError:            return "网络不可用，AI 优化暂不可用"
        case .providerError(let m):    return "AI 优化失败：\(m)"
        }
    }
}

/// High-level translation state machine (PRD §14.3).
enum TranslationPhase: Equatable {
    case idle
    case checkingLanguagePack
    case languagePackRequired
    case preparingLanguagePack
    case translating
    case translated
    case optimizing
    case optimized
    case failed(TranslationError)
}
