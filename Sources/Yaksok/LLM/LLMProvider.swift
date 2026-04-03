import Foundation

// MARK: - LLM Model

struct LLMModel: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let supportsVision: Bool

    init(id: String, displayName: String, supportsVision: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.supportsVision = supportsVision
    }
}

// MARK: - LLM Provider ID

enum LLMProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case gemini
    case openai
    case claude
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openai: "OpenAI"
        case .claude: "Anthropic Claude"
        case .apple: "Apple Intelligence"
        }
    }

    var keychainKey: String {
        "apiKey_\(rawValue)"
    }

    var defaultModels: [LLMModel] {
        switch self {
        case .gemini:
            [
                LLMModel(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash"),
                LLMModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                LLMModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro"),
            ]
        case .openai:
            [
                LLMModel(id: "gpt-4o-mini", displayName: "GPT-4o mini"),
                LLMModel(id: "gpt-4o", displayName: "GPT-4o"),
                LLMModel(id: "gpt-4.1-mini", displayName: "GPT-4.1 mini"),
                LLMModel(id: "gpt-4.1", displayName: "GPT-4.1"),
            ]
        case .claude:
            [
                LLMModel(id: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4"),
                LLMModel(id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5"),
            ]
        case .apple:
            [
                LLMModel(id: "apple-intelligence", displayName: "Apple Intelligence", supportsVision: true),
            ]
        }
    }
}

// MARK: - LLM Provider Protocol

protocol LLMProvider: Sendable {
    var providerID: LLMProviderID { get }
    var supportedModels: [LLMModel] { get }

    func extractSchedule(from text: String, model: LLMModel) async throws -> ScheduleEvent
    func extractSchedule(from imageData: Data, model: LLMModel) async throws -> ScheduleEvent
}

extension LLMProvider {
    var displayName: String { providerID.displayName }
}
