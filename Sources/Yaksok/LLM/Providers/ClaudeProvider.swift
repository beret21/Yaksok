import Foundation

struct ClaudeProvider: LLMProvider {
    let providerID = LLMProviderID.claude
    let supportedModels = LLMProviderID.claude.defaultModels

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func extractSchedule(from text: String, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()

        let messages: [[String: Any]] = [
            ["role": "user", "content": text],
        ]

        let responseText = try await callClaude(
            apiKey: apiKey, model: model.id,
            system: SchedulePrompt.prompt(),
            messages: messages
        )
        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    func extractSchedule(from imageData: Data, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()
        let base64 = imageData.base64EncodedString()

        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64,
                        ],
                    ] as [String: Any]
                ] as [[String: Any]],
            ]
        ]

        let responseText = try await callClaude(
            apiKey: apiKey, model: model.id,
            system: SchedulePrompt.prompt(),
            messages: messages
        )
        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    // MARK: - Private

    private func requireAPIKey() throws -> String {
        guard let key = KeychainManager.load(key: LLMProviderID.claude.keychainKey),
              !key.isEmpty
        else { throw LLMError.noAPIKey }
        return key
    }

    private func callClaude(
        apiKey: String, model: String,
        system: String, messages: [[String: Any]]
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": messages,
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
                Log.llm.error("Claude error: \(serverMsg)")
                throw LLMError.serverError(statusCode: httpResponse.statusCode, message: serverMsg)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
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
