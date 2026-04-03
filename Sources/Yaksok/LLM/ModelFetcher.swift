import Foundation

/// API에서 프로바이더별 모델 목록을 가져옴
enum ModelFetcher {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Gemini

    static func fetchGeminiModels(apiKey: String) async -> [LLMModel] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }

            return models.compactMap { model -> LLMModel? in
                guard let name = model["name"] as? String,
                      let displayName = model["displayName"] as? String else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                // gemini 모델만 필터
                guard id.hasPrefix("gemini") else { return nil }
                let methods = model["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent") else { return nil }
                return LLMModel(id: id, displayName: displayName)
            }
            .sorted { $0.id > $1.id }  // 최신 모델 먼저
        } catch {
            Log.debug("[ModelFetcher] Gemini fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - OpenAI

    static func fetchOpenAIModels(apiKey: String) async -> [LLMModel] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else { return [] }

            return models.compactMap { model -> LLMModel? in
                guard let id = model["id"] as? String else { return nil }
                // gpt 모델만 필터 (chat completion 가능한 것)
                guard id.hasPrefix("gpt-") else { return nil }
                // 임시/내부 모델 제외
                guard !id.contains("instruct"), !id.contains("realtime"), !id.contains("audio") else { return nil }
                return LLMModel(id: id, displayName: id)
            }
            .sorted { $0.id > $1.id }
        } catch {
            Log.debug("[ModelFetcher] OpenAI fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Claude (Anthropic)

    static func fetchClaudeModels(apiKey: String) async -> [LLMModel] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=100") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else { return [] }

            return models.compactMap { model -> LLMModel? in
                guard let id = model["id"] as? String else { return nil }
                // claude 모델만 필터
                guard id.hasPrefix("claude-") else { return nil }
                let displayName = model["display_name"] as? String ?? id
                return LLMModel(id: id, displayName: displayName)
            }
            .sorted { $0.id > $1.id }
        } catch {
            Log.debug("[ModelFetcher] Claude fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Fetch for Provider

    static func fetchModels(for provider: LLMProviderID) async -> [LLMModel]? {
        guard provider != .apple else { return nil }

        let apiKey = KeychainManager.load(key: provider.keychainKey)
        guard let key = apiKey, !key.isEmpty else { return nil }

        let models: [LLMModel]
        switch provider {
        case .gemini:
            models = await fetchGeminiModels(apiKey: key)
        case .openai:
            models = await fetchOpenAIModels(apiKey: key)
        case .claude:
            models = await fetchClaudeModels(apiKey: key)
        case .apple:
            return nil
        }
        return models.isEmpty ? nil : models
    }
}
