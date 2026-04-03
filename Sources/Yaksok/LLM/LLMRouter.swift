import Foundation

/// Routes LLM requests to the configured provider
@MainActor
final class LLMRouter {
    private let providers: [LLMProviderID: any LLMProvider] = [
        .gemini: GeminiProvider(),
        .openai: OpenAIProvider(),
        .claude: ClaudeProvider(),
        .apple: AppleProvider(),
    ]

    func extract(from text: String, providerID: LLMProviderID, model: LLMModel) async throws -> ScheduleEvent {
        guard let provider = providers[providerID] else {
            throw LLMError.unsupportedModel
        }
        Log.llm.info("Extracting from text via \(providerID.displayName) / \(model.id)")
        return try await provider.extractSchedule(from: text, model: model)
    }

    func extract(from imageData: Data, providerID: LLMProviderID, model: LLMModel) async throws -> ScheduleEvent {
        guard let provider = providers[providerID] else {
            throw LLMError.unsupportedModel
        }
        guard model.supportsVision else {
            throw LLMError.unsupportedModel
        }
        Log.llm.info("Extracting from image via \(providerID.displayName) / \(model.id)")
        return try await provider.extractSchedule(from: imageData, model: model)
    }

    func availableModels(for providerID: LLMProviderID) -> [LLMModel] {
        providerID.defaultModels
    }
}
