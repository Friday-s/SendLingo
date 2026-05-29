import Foundation

/// One stored translation (PRD §7.4 / §13.3, AC-HS-06).
struct TranslationHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceText: String        // 原中文
    let targetLanguage: String    // 目标语言 code
    let systemTranslation: String // 系统译文
    let aiTranslation: String?    // AI 优化译文（可空）
    let tone: String?             // 语气
    let createdAt: Date           // 创建时间

    init(id: UUID = UUID(),
         sourceText: String,
         targetLanguage: String,
         systemTranslation: String,
         aiTranslation: String? = nil,
         tone: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.sourceText = sourceText
        self.targetLanguage = targetLanguage
        self.systemTranslation = systemTranslation
        self.aiTranslation = aiTranslation
        self.tone = tone
        self.createdAt = createdAt
    }
}
