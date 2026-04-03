import Foundation
import Observation

/// Central app state — @Observable for SwiftUI binding
@Observable
@MainActor
final class AppState {

    // MARK: - LLM Configuration

    var selectedProvider: LLMProviderID {
        didSet { savePreferences() }
    }
    var selectedModelID: String {
        didSet { savePreferences() }
    }

    var selectedModel: LLMModel {
        selectedProvider.defaultModels.first { $0.id == selectedModelID }
            ?? selectedProvider.defaultModels[0]
    }

    // MARK: - Recent History

    enum HistoryStatus: String, Codable {
        case recognized   // LLM 추출 완료 (폼 표시됨)
        case registered   // 캘린더 등록 완료
        case cancelled    // 사용자가 폼 닫기/취소
    }

    struct HistoryItem: Codable, Identifiable {
        let id: UUID
        var title: String
        var date: String
        var status: HistoryStatus
        let providerName: String
        let timestamp: Date

        init(title: String, date: String, status: HistoryStatus = .recognized, providerName: String = "") {
            self.id = UUID()
            self.title = title
            self.date = date
            self.status = status
            self.providerName = providerName
            self.timestamp = Date()
        }
    }

    var recentHistory: [HistoryItem] = []
    private static let maxHistory = 100
    private static let maxAgeDays = 90

    /// LLM 추출 완료 시 호출 — .recognized 상태로 기록
    func recordRecognized(title: String, date: String, providerName: String) -> UUID {
        let item = HistoryItem(title: title, date: date, status: .recognized, providerName: providerName)
        recentHistory.insert(item, at: 0)
        trimAndSave()
        return item.id
    }

    /// 캘린더 등록 완료 시 호출 — .registered로 업데이트
    func updateToRegistered(id: UUID, title: String, date: String) {
        if let idx = recentHistory.firstIndex(where: { $0.id == id }) {
            recentHistory[idx].status = .registered
            recentHistory[idx].title = title
            recentHistory[idx].date = date
        }
        saveHistory()
    }

    /// 폼 취소 시 호출 — .cancelled로 업데이트
    func updateToCancelled(id: UUID) {
        if let idx = recentHistory.firstIndex(where: { $0.id == id }) {
            recentHistory[idx].status = .cancelled
        }
        saveHistory()
    }

    /// 히스토리 전체 삭제
    func clearHistory() {
        recentHistory.removeAll()
        saveHistory()
    }

    /// 메뉴바 표시용: .registered만 최근 5개
    var registeredHistory: [HistoryItem] {
        Array(recentHistory.filter { $0.status == .registered }.prefix(5))
    }

    private func trimAndSave() {
        if recentHistory.count > Self.maxHistory {
            recentHistory = Array(recentHistory.prefix(Self.maxHistory))
        }
        saveHistory()
    }

    /// 90일 이상 된 항목 자동 삭제
    func pruneHistory() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.maxAgeDays, to: Date()) ?? Date()
        let before = recentHistory.count
        recentHistory.removeAll { $0.timestamp < cutoff }
        if recentHistory.count != before {
            saveHistory()
            Log.debug("[History] Pruned \(before - recentHistory.count) old items")
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(recentHistory) {
            UserDefaults.standard.set(data, forKey: "recentHistory")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "recentHistory"),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return }
        recentHistory = items
    }

    // MARK: - Dynamic Model List

    /// 프로바이더별 API에서 가져온 모델 목록 캐시
    var fetchedModels: [LLMProviderID: [LLMModel]] = [:]
    var isFetchingModels = false

    /// 현재 프로바이더의 모델 목록 (API 결과 우선, 없으면 기본)
    func modelsForProvider(_ provider: LLMProviderID) -> [LLMModel] {
        fetchedModels[provider] ?? provider.defaultModels
    }

    /// API에서 모델 목록 가져와서 캐시
    func refreshModels(for provider: LLMProviderID) async {
        isFetchingModels = true
        if let models = await ModelFetcher.fetchModels(for: provider) {
            fetchedModels[provider] = models
            saveFetchedModels()
            Log.debug("[Models] Fetched \(models.count) models for \(provider.displayName)")
        }
        isFetchingModels = false
    }

    private func saveFetchedModels() {
        var dict: [String: [[String: Any]]] = [:]
        for (provider, models) in fetchedModels {
            dict[provider.rawValue] = models.map { ["id": $0.id, "displayName": $0.displayName] }
        }
        UserDefaults.standard.set(dict, forKey: "fetchedModels")
        UserDefaults.standard.set(Date(), forKey: "fetchedModelsDate")
    }

    private func loadFetchedModels() {
        guard let dict = UserDefaults.standard.dictionary(forKey: "fetchedModels") as? [String: [[String: Any]]] else { return }
        for (key, arr) in dict {
            guard let provider = LLMProviderID(rawValue: key) else { continue }
            let models = arr.compactMap { item -> LLMModel? in
                guard let id = item["id"] as? String, let name = item["displayName"] as? String else { return nil }
                return LLMModel(id: id, displayName: name)
            }
            if !models.isEmpty { fetchedModels[provider] = models }
        }
    }

    /// 1주 경과 시 자동 새로고침 필요 여부
    var needsModelRefresh: Bool {
        guard let date = UserDefaults.standard.object(forKey: "fetchedModelsDate") as? Date else { return true }
        return Date().timeIntervalSince(date) > 7 * 24 * 3600
    }

    // MARK: - Default Meeting Duration (minutes)

    var defaultDurationMinutes: Int = 60 {
        didSet { UserDefaults.standard.set(defaultDurationMinutes, forKey: "defaultDurationMinutes") }
    }

    static let durationOptions = [15, 30, 60, 90, 120]

    // MARK: - Conflict Check Calendars

    var conflictCheckCalendarIDs: Set<String> = [] {
        didSet { saveConflictCalendars() }
    }

    private func saveConflictCalendars() {
        let array = Array(conflictCheckCalendarIDs)
        UserDefaults.standard.set(array, forKey: "conflictCheckCalendarIDs")
    }

    private func loadConflictCalendars() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: "conflictCheckCalendarIDs") ?? []
        return Set(array)
    }

    /// 삭제된 캘린더 ID를 conflictCheckCalendarIDs에서 제거
    func pruneConflictCalendarIDs(validIDs: Set<String>) {
        let stale = conflictCheckCalendarIDs.subtracting(validIDs)
        if !stale.isEmpty {
            conflictCheckCalendarIDs = conflictCheckCalendarIDs.intersection(validIDs)
        }
    }

    // MARK: - Processing State

    var isProcessing = false
    var extractedEvent: ScheduleEvent?
    var showScheduleForm = false
    var showError = false
    var lastError: String?
    var showSettings = false

    /// 재분석용: LLM에 전달된 원본 텍스트 보존
    var lastInputText: String?

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        let providerRaw = defaults.string(forKey: "selectedProvider") ?? "apple"
        self.selectedProvider = LLMProviderID(rawValue: providerRaw) ?? .apple
        self.selectedModelID = defaults.string(forKey: "selectedModelID")
            ?? LLMProviderID.apple.defaultModels[0].id
        let storedDuration = defaults.integer(forKey: "defaultDurationMinutes")
        self.defaultDurationMinutes = storedDuration > 0 ? storedDuration : 60
        let calIDs = defaults.stringArray(forKey: "conflictCheckCalendarIDs") ?? []
        self.conflictCheckCalendarIDs = Set(calIDs)
        loadHistory()
        pruneHistory()
        loadFetchedModels()
    }

    // MARK: - Persistence

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
        defaults.set(selectedModelID, forKey: "selectedModelID")
    }

    // MARK: - Helpers

    func hasAPIKey(for provider: LLMProviderID) -> Bool {
        guard provider != .apple else { return true }
        return KeychainManager.load(key: provider.keychainKey) != nil
    }

    func resetProcessingState() {
        isProcessing = false
        extractedEvent = nil
        showScheduleForm = false
        showError = false
        lastError = nil
        lastInputText = nil
    }
}
