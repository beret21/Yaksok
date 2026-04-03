import Foundation
import FoundationModels

/// Apple Intelligence provider using FoundationModels
/// 현재: 자유 텍스트 → JSON 파싱 (안정적)
/// TODO: @Generable constrained decoding 전환 (GenerableSchedule 준비됨, 추가 테스트 필요)
struct AppleProvider: LLMProvider {
    let providerID = LLMProviderID.apple
    let supportedModels = LLMProviderID.apple.defaultModels

    func extractSchedule(from text: String, model: LLMModel) async throws -> ScheduleEvent {
        let prompt = SchedulePrompt.prompt() + "\n\n텍스트:\n\(text)"

        Log.debug("[Apple] Text extraction, prompt: \(prompt.count) chars")
        let start = Date()

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let responseText = response.content

            let elapsed = Date().timeIntervalSince(start)
            Log.debug("[Apple] Response in \(String(format: "%.1f", elapsed))s")

            return try ScheduleEvent.fromLLMResponse(responseText)
        } catch let error as LLMError {
            throw error  // 이미 LLMError면 그대로 전달
        } catch {
            let nsError = error as NSError
            Log.debug("[Apple] Error: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
            throw LLMError.appleIntelligenceError(underlying: error)
        }
    }

    func extractSchedule(from imageData: Data, model: LLMModel) async throws -> ScheduleEvent {
        let ocrText = try await OCRReader.recognizeText(from: imageData)
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noScheduleFound
        }
        return try await extractSchedule(from: "[이미지에서 추출된 텍스트]\n\(ocrText)", model: model)
    }
}

// MARK: - @Generable (향후 전환용, 추가 테스트 필요)

// @Generable
// struct GenerableSchedule {
//     @Guide(description: "일정 제목")
//     var title: String
//     @Guide(description: "시작 날짜 YYYY-MM-DD")
//     var startDate: String
//     @Guide(description: "시작 시간 HH:MM")
//     var startTime: String
//     @Guide(description: "종료 날짜 YYYY-MM-DD")
//     var endDate: String
//     @Guide(description: "종료 시간 HH:MM")
//     var endTime: String
//     @Guide(description: "종일 여부")
//     var allDay: Bool
//     @Guide(description: "장소")
//     var location: String
//     @Guide(description: "메모")
//     var notes: String
// }
