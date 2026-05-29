import Foundation

/// Writing tone applied **only** to the AI optimization layer (PRD §10.3, AC-AI-04).
/// The default system translation never uses tone.
enum Tone: String, CaseIterable, Codable, Identifiable {
    case casual    // 口语 — default (FIX-4 / AC-AI-05)
    case formal    // 正式
    case business  // 商务

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .casual:   return "口语"
        case .formal:   return "正式"
        case .business: return "商务"
        }
    }

    /// Prompt modifier appended to the system prompt (PRD §10.3).
    var promptModifier: String {
        switch self {
        case .formal:
            return "Use formal, precise, polished language suitable for official documents or formal communication."
        case .casual:
            return "Use natural, conversational phrasing as a native speaker would say in everyday messaging."
        case .business:
            return "Use professional, courteous, concise business language suitable for work emails and customer communication."
        }
    }
}
