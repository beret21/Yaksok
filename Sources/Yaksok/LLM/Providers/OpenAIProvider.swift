import Foundation

struct OpenAIProvider: LLMProvider {
    let providerID = LLMProviderID.openai
    let supportedModels = LLMProviderID.openai.defaultModels

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func extractSchedule(from text: String, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()

        let messages: [[String: Any]] = [
            ["role": "system", "content": SchedulePrompt.prompt()],
            ["role": "user", "content": text],
        ]

        let responseText = try await callOpenAI(apiKey: apiKey, model: model.id, messages: messages)
        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    func extractSchedule(from imageData: Data, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()
        let base64 = imageData.base64EncodedString()

        let messages: [[String: Any]] = [
            ["role": "system", "content": SchedulePrompt.prompt()],
            [
                "role": "user",
                "content": [
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(base64)"],
                    ] as [String: Any]
                ] as [[String: Any]],
            ],
        ]

        let responseText = try await callOpenAI(apiKey: apiKey, model: model.id, messages: messages)
        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    // MARK: - Private

    private func requireAPIKey() throws -> String {
        guard let key = KeychainManager.load(key: LLMProviderID.openai.keychainKey),
              !key.isEmpty
        else { throw LLMError.noAPIKey }
        return key
    }

    private func callOpenAI(apiKey: String, model: String, messages: [[String: Any]]) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200: break
            case 401:
                throw LLMError.authenticationFailed
            case 429:
                throw LLMError.rateLimitExceeded
            default:
                let serverMsg = Self.parseErrorMessage(data) ?? "HTTP \(httpResponse.statusCode)"
                Log.llm.error("OpenAI error: \(serverMsg)")
                throw LLMError.serverError(statusCode: httpResponse.statusCode, message: serverMsg)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else {
            let raw = String(data: data, encoding: .utf8) ?? "Empty"
            throw LLMError.invalidResponse(raw: raw)
        }

        return text
    }

    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }
}
