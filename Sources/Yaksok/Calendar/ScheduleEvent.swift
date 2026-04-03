import Foundation

struct ScheduleEvent: Codable, Sendable {
    let title: String?
    let startDate: String?
    let startTime: String?
    let endDate: String?
    let endTime: String?
    let allDay: Bool?
    let location: String?
    let notes: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startDate = "start_date"
        case startTime = "start_time"
        case endDate = "end_date"
        case endTime = "end_time"
        case allDay = "all_day"
        case location
        case notes
        case error
    }

    var hasSchedule: Bool {
        title != nil && startDate != nil && error == nil
    }
}

// MARK: - Date parsing

extension ScheduleEvent {
    func parsedStartDate() -> Date? {
        guard let dateStr = startDate else { return nil }
        return Self.parseDate(dateStr, allDay == true ? nil : startTime)
    }

    func parsedEndDate() -> Date? {
        guard let dateStr = endDate else { return nil }
        return Self.parseDate(dateStr, allDay == true ? nil : endTime)
    }

    static func parseDate(_ dateStr: String, _ timeStr: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let timeStr, !timeStr.isEmpty {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.date(from: "\(dateStr) \(timeStr)")
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr)
        }
    }
}

// MARK: - JSON response parsing

extension ScheduleEvent {
    /// Parse LLM response text to ScheduleEvent, stripping markdown fences
    static func fromLLMResponse(_ text: String) throws -> ScheduleEvent {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.debug("[Parse] LLM response: \(cleaned.count) chars")

        // Strip markdown code fences (```json ... ```)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.last?.hasPrefix("```") == true {
                cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
            } else {
                cleaned = lines.dropFirst().joined(separator: "\n")
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract JSON from mixed text (LLM might add explanation before/after JSON)
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[jsonStart...jsonEnd])
        } else if let jsonStart = cleaned.firstIndex(of: "["),
                  let jsonEnd = cleaned.lastIndex(of: "]") {
            // Array response — extract first object
            cleaned = String(cleaned[jsonStart...jsonEnd])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw LLMError.invalidResponse(raw: text)
        }

        Log.debug("[Parse] Extracted JSON: \(cleaned.count) chars")
        if let event = try? JSONDecoder().decode(ScheduleEvent.self, from: data) {
            if event.error != nil {
                throw LLMError.noScheduleFound
            }
            if event.hasSchedule {
                return event
            }
        }

        // Try decoding as array of events (take first one)
        if let events = try? JSONDecoder().decode([ScheduleEvent].self, from: data),
           let first = events.first(where: { $0.hasSchedule }) {
            return first
        }

        // Last resort: try lenient parsing with JSONSerialization
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let event = ScheduleEvent(
                title: jsonObj["title"] as? String,
                startDate: jsonObj["start_date"] as? String,
                startTime: jsonObj["start_time"] as? String,
                endDate: jsonObj["end_date"] as? String,
                endTime: jsonObj["end_time"] as? String,
                allDay: jsonObj["all_day"] as? Bool,
                location: jsonObj["location"] as? String,
                notes: jsonObj["notes"] as? String,
                error: jsonObj["error"] as? String
            )
            if event.hasSchedule { return event }
            if event.error != nil { throw LLMError.noScheduleFound }
        }

        Log.llm.error("Failed to parse LLM response: \(cleaned.prefix(200))")
        throw LLMError.invalidResponse(raw: String(cleaned.prefix(200)))
    }
}
