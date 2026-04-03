import Foundation

struct GeminiProvider: LLMProvider {
    let providerID = LLMProviderID.gemini
    let supportedModels = LLMProviderID.gemini.defaultModels

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60  // 2.5 Pro can be slower
        return URLSession(configuration: config)
    }()

    func extractSchedule(from text: String, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()
        let prompt = SchedulePrompt.prompt() + "\n\n텍스트:\n\(text)"

        Log.debug("[Gemini] Text extraction — model: \(model.id), length: \(text.count) chars")

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ]
        ]

        let start = Date()
        let responseText = try await callGemini(apiKey: apiKey, model: model.id, body: body)
        let elapsed = Date().timeIntervalSince(start)
        Log.debug("[Gemini] Response in \(String(format: "%.1f", elapsed))s")

        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    func extractSchedule(from imageData: Data, model: LLMModel) async throws -> ScheduleEvent {
        let apiKey = try requireAPIKey()
        let prompt = SchedulePrompt.prompt()
        let base64 = imageData.base64EncodedString()

        Log.debug("[Gemini] Image extraction — model: \(model.id), image: \(imageData.count) bytes")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inlineData": [
                                "mimeType": "image/jpeg",
                                "data": base64,
                            ]
                        ],
                    ]
                ]
            ]
        ]

        let start = Date()
        let responseText = try await callGemini(apiKey: apiKey, model: model.id, body: body)
        let elapsed = Date().timeIntervalSince(start)
        Log.debug("[Gemini] Response in \(String(format: "%.1f", elapsed))s")

        return try ScheduleEvent.fromLLMResponse(responseText)
    }

    // MARK: - Private

    private func requireAPIKey() throws -> String {
        guard let key = KeychainManager.load(key: LLMProviderID.gemini.keychainKey),
              !key.isEmpty
        else {
            throw LLMError.noAPIKey
        }
        return key
    }

    private func callGemini(apiKey: String, model: String, body: [String: Any]) async throws -> String {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw LLMError.networkError(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.debug("[Gemini] POST \(model):generateContent — body: \(request.httpBody?.count ?? 0) bytes")

        let (data, response) = try await Self.session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            Log.debug("[Gemini] HTTP \(httpResponse.statusCode) — response: \(data.count) bytes")
            switch httpResponse.statusCode {
            case 200: break
            case 401, 403:
                Log.debug("[Gemini] Auth error (HTTP \(httpResponse.statusCode))")
                throw LLMError.authenticationFailed
            case 429:
                throw LLMError.rateLimitExceeded
            default:
                // 서버 에러 본문에서 메시지 추출
                let serverMsg = Self.parseErrorMessage(data) ?? "HTTP \(httpResponse.statusCode)"
                Log.debug("[Gemini] Error: \(serverMsg)")
                throw LLMError.serverError(statusCode: httpResponse.statusCode, message: serverMsg)
            }
        }

        // Parse Gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            let raw = String(data: data, encoding: .utf8) ?? "Empty"
            Log.debug("[Gemini] Failed to parse response structure (\(raw.count) chars)")
            throw LLMError.invalidResponse(raw: raw)
        }

        return text
    }

    /// Gemini API 에러 응답에서 메시지 추출
    private static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return nil }
        return message
    }
}
