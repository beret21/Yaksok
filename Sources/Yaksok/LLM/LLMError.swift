import Foundation

enum LLMError: LocalizedError {
    case noAPIKey
    case authenticationFailed
    case rateLimitExceeded
    case networkError(underlying: Error)
    case serverError(statusCode: Int, message: String)
    case invalidResponse(raw: String)
    case noScheduleFound
    case unsupportedModel
    case imageEncodingFailed
    case timeout
    case appleIntelligenceError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return String(localized: "API 키가 설정되지 않았습니다. 설정에서 API 키를 입력해 주세요.", comment: "LLM error")
        case .authenticationFailed:
            return String(localized: "API 키 인증에 실패했습니다. 설정에서 API 키를 확인해 주세요.", comment: "LLM error")
        case .rateLimitExceeded:
            return String(localized: "API 요청 한도를 초과했습니다. 잠시 후 다시 시도해 주세요.", comment: "LLM error")
        case .networkError(let underlying):
            let nsError = underlying as NSError
            if nsError.code == NSURLErrorTimedOut {
                return String(localized: "네트워크 타임아웃. 인터넷 연결을 확인하고 다시 시도해 주세요.", comment: "LLM error")
            }
            if nsError.code == NSURLErrorNotConnectedToInternet {
                return String(localized: "인터넷 연결이 없습니다. Wi-Fi 또는 네트워크를 확인해 주세요.", comment: "LLM error")
            }
            return String(localized: "네트워크 오류. 인터넷 연결을 확인해 주세요.", comment: "LLM error")
        case .serverError(let statusCode, let message):
            return String(localized: "서버 오류 (\(statusCode)): \(message)", comment: "LLM error")
        case .invalidResponse(let raw):
            return String(localized: "LLM 응답을 파싱할 수 없습니다. 다시 시도하거나 다른 모델로 재분석해 보세요.\n응답: \(raw.prefix(80))", comment: "LLM error")
        case .noScheduleFound:
            return String(localized: "일정 정보를 찾을 수 없습니다. 텍스트에 날짜/시간이 포함되어 있는지 확인해 주세요.", comment: "LLM error")
        case .unsupportedModel:
            return String(localized: "지원하지 않는 모델입니다.", comment: "LLM error")
        case .imageEncodingFailed:
            return String(localized: "이미지 인코딩에 실패했습니다. 다른 이미지를 시도해 주세요.", comment: "LLM error")
        case .timeout:
            return String(localized: "요청 시간이 초과했습니다. 다시 시도해 주세요.", comment: "LLM error")
        case .appleIntelligenceError:
            return String(localized: "Apple Intelligence를 사용할 수 없습니다. 시스템 설정 > Apple Intelligence에서 활성화 여부를 확인하거나, 설정에서 Gemini 등 외부 LLM으로 전환해 주세요.", comment: "LLM error")
        }
    }
}
