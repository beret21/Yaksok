import EventKit
import ServiceManagement
import Sparkle
import SwiftUI

/// Settings window — adapted from MacTR/SettingsView.swift
struct SettingsView: View {
    @Bindable var appState: AppState
    let updater: SPUUpdater
    var onHotkeyChanged: (() -> Void)?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var conflictCalendarManager = CalendarManager()

    var body: some View {
        TabView {
            llmSettings
                .tabItem {
                    Label(String(localized: "LLM", comment: "LLM settings tab"), systemImage: "brain")
                }

            apiKeySettings
                .tabItem {
                    Label(String(localized: "API 키", comment: "API keys tab"), systemImage: "key")
                }

            hotkeySettings
                .tabItem {
                    Label(String(localized: "단축키", comment: "Hotkeys tab"), systemImage: "keyboard")
                }

            historyView
                .tabItem {
                    Label(String(localized: "히스토리", comment: "History tab"), systemImage: "clock.arrow.circlepath")
                }

            aboutView
                .tabItem {
                    Label(String(localized: "정보", comment: "About tab"), systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 520)
    }

    // MARK: - LLM Tab

    private var llmSettings: some View {
        Form {
            Section(String(localized: "일반", comment: "General section")) {
                Toggle(String(localized: "로그인 시 자동 시작", comment: "Launch at login"),
                       isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            Log.debug("[Settings] Launch at login error: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text(".app 번들로 실행해야 동작합니다", comment: "Launch at login note")
                    .font(.caption)

                Picker(String(localized: "기본 회의 시간", comment: "Default meeting duration"),
                       selection: $appState.defaultDurationMinutes) {
                    ForEach(AppState.durationOptions, id: \.self) { min in
                        Text(min < 60 ? "\(min)분" : "\(min / 60)시간")
                            .tag(min)
                    }
                }

                if appState.conflictCheckCalendarIDs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("일정 충돌 체크: 아래 '일정 충돌 체크' 섹션에서 캘린더를 선택하세요", comment: "Conflict check hint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("충돌 체크 캘린더 \(appState.conflictCheckCalendarIDs.count)개 선택됨", comment: "Conflict calendars selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(String(localized: "서비스 제공자", comment: "Provider section")) {
                Picker(String(localized: "프로바이더", comment: "Provider picker"),
                       selection: $appState.selectedProvider) {
                    ForEach(LLMProviderID.allCases) { provider in
                        if provider == .apple {
                            Text("\(provider.displayName) (macOS 26+)")
                                .tag(provider)
                        } else {
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }
                .onChange(of: appState.selectedProvider) { _, newProvider in
                    appState.selectedModelID = newProvider.defaultModels[0].id
                }
            }

            Section(String(localized: "모델", comment: "Model section")) {
                HStack {
                    Picker(String(localized: "모델", comment: "Model picker"),
                           selection: $appState.selectedModelID) {
                        ForEach(appState.modelsForProvider(appState.selectedProvider)) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }

                    if appState.selectedProvider != .apple {
                        Button {
                            Task { await appState.refreshModels(for: appState.selectedProvider) }
                        } label: {
                            if appState.isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.isFetchingModels || !appState.hasAPIKey(for: appState.selectedProvider))
                        .help(String(localized: "API에서 모델 목록 새로고침", comment: "Refresh models tooltip"))
                    }
                }
            }

            Section {
                if appState.selectedProvider == .apple {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "apple.intelligence")
                                .foregroundColor(.blue)
                            Text("API 키 불필요 (기기 내장 모델)", comment: "Apple Intelligence no key")
                                .font(.callout)
                        }
                        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) — Apple Intelligence 사용 가능", comment: "Apple supported")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text("macOS 26 이상 필요 (현재: \(ProcessInfo.processInfo.operatingSystemVersionString))", comment: "Apple unsupported")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        Text("이미지: Vision OCR → Apple Intelligence 파이프라인", comment: "Apple Intelligence pipeline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: appState.hasAPIKey(for: appState.selectedProvider)
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(appState.hasAPIKey(for: appState.selectedProvider)
                                             ? .green : .orange)
                        Text(appState.hasAPIKey(for: appState.selectedProvider)
                             ? String(localized: "API 키 설정됨", comment: "API key set")
                             : String(localized: "API 키 미설정", comment: "API key not set"))
                    }
                }
            }

            Section(String(localized: "일정 충돌 체크", comment: "Conflict check section")) {
                if conflictCalendarManager.accessGranted {
                    let allCals = conflictCalendarManager.allCalendars()
                    if allCals.isEmpty {
                        Text("캘린더가 없습니다", comment: "No calendars")
                            .foregroundColor(.secondary)
                    } else {
                        let grouped = Dictionary(grouping: allCals) { $0.source?.title ?? "기타" }
                        ForEach(grouped.keys.sorted(), id: \.self) { sourceName in
                            DisclosureGroup(sourceName) {
                                ForEach(grouped[sourceName] ?? [], id: \.calendarIdentifier) { cal in
                                    Toggle(isOn: Binding(
                                        get: { appState.conflictCheckCalendarIDs.contains(cal.calendarIdentifier) },
                                        set: { enabled in
                                            if enabled {
                                                appState.conflictCheckCalendarIDs.insert(cal.calendarIdentifier)
                                            } else {
                                                appState.conflictCheckCalendarIDs.remove(cal.calendarIdentifier)
                                            }
                                        }
                                    )) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(nsColor: cal.color))
                                                .frame(width: 10, height: 10)
                                            Text(cal.title)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("캘린더 접근 권한이 필요합니다", comment: "Calendar permission needed")
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            Button(String(localized: "권한 요청", comment: "Request permission")) {
                                conflictCalendarManager.requestAccess()
                            }
                            Button(String(localized: "시스템 설정 열기", comment: "Open System Settings")) {
                                conflictCalendarManager.openSystemSettings()
                            }
                        }
                        .font(.caption)
                    }
                }
                Text("선택한 캘린더의 기존 일정이 등록 폼에 표시됩니다", comment: "Conflict check note")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onAppear { conflictCalendarManager.requestAccess() }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - API Key Tab

    @State private var geminiKey: String = ""
    @State private var openaiKey: String = ""
    @State private var claudeKey: String = ""
    @State private var showSavedMessage: Bool = false

    private var apiKeySettings: some View {
        Form {
            Section("Google Gemini") {
                SecureField("API Key", text: $geminiKey)
                    .onAppear { geminiKey = KeychainManager.load(key: LLMProviderID.gemini.keychainKey) ?? "" }
            }

            Section("OpenAI") {
                SecureField("API Key", text: $openaiKey)
                    .onAppear { openaiKey = KeychainManager.load(key: LLMProviderID.openai.keychainKey) ?? "" }
            }

            Section("Anthropic Claude") {
                SecureField("API Key", text: $claudeKey)
                    .onAppear { claudeKey = KeychainManager.load(key: LLMProviderID.claude.keychainKey) ?? "" }
            }

            Section {
                HStack {
                    Button(String(localized: "저장", comment: "Save button")) {
                        saveAPIKeys()
                    }
                    .buttonStyle(.borderedProminent)

                    if showSavedMessage {
                        Text("저장됨", comment: "Saved message")
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveAPIKeys() {
        let keys: [(String, LLMProviderID)] = [
            (geminiKey, .gemini),
            (openaiKey, .openai),
            (claudeKey, .claude),
        ]

        for (value, provider) in keys {
            if value.isEmpty {
                KeychainManager.delete(key: provider.keychainKey)
            } else {
                try? KeychainManager.save(key: provider.keychainKey, value: value)
            }
        }

        withAnimation { showSavedMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedMessage = false }
        }
    }

    // MARK: - Hotkey Tab

    @State private var clipboardHotkey = HotkeyConfig.loadAll().clipboard
    @State private var captureHotkey = HotkeyConfig.loadAll().capture
    @State private var selectedTextHotkey = HotkeyConfig.loadAll().selectedText
    @State private var hotkeysSaved = false

    private var hotkeySettings: some View {
        Form {
            Section(String(localized: "전역 단축키", comment: "Global hotkeys section")) {
                KeyRecorderView(
                    label: String(localized: "클립보드 추출", comment: "Clipboard hotkey"),
                    config: $clipboardHotkey
                )
                KeyRecorderView(
                    label: String(localized: "화면 캡처", comment: "Capture hotkey"),
                    config: $captureHotkey
                )
                KeyRecorderView(
                    label: String(localized: "선택 텍스트", comment: "Selected text hotkey"),
                    config: $selectedTextHotkey
                )
            }

            Section {
                HStack {
                    Button(String(localized: "저장", comment: "Save hotkeys")) {
                        HotkeyConfig.saveAll(
                            clipboard: clipboardHotkey,
                            capture: captureHotkey,
                            selectedText: selectedTextHotkey
                        )
                        onHotkeyChanged?()
                        withAnimation { hotkeysSaved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { hotkeysSaved = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "기본값 복원", comment: "Reset hotkeys")) {
                        clipboardHotkey = .defaultClipboard
                        captureHotkey = .defaultCapture
                        selectedTextHotkey = .defaultSelectedText
                        HotkeyConfig.resetAll()
                        onHotkeyChanged?()
                    }

                    if hotkeysSaved {
                        Text("저장됨", comment: "Saved")
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - History Tab

    @State private var historyFilter: AppState.HistoryStatus? = nil

    private var filteredHistory: [AppState.HistoryItem] {
        if let filter = historyFilter {
            return appState.recentHistory.filter { $0.status == filter }
        }
        return appState.recentHistory
    }

    private var historyView: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                filterButton(title: String(localized: "전체", comment: "All filter"), filter: nil)
                filterButton(title: String(localized: "등록", comment: "Registered filter"), filter: .registered)
                filterButton(title: String(localized: "인식", comment: "Recognized filter"), filter: .recognized)
                filterButton(title: String(localized: "취소", comment: "Cancelled filter"), filter: .cancelled)
                Spacer()
                Button(role: .destructive) {
                    appState.clearHistory()
                } label: {
                    Label(String(localized: "전체 삭제", comment: "Clear history"), systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(appState.recentHistory.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // List
            if filteredHistory.isEmpty {
                Spacer()
                Text("히스토리가 없습니다", comment: "No history")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(filteredHistory) { item in
                    HStack {
                        statusBadge(item.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(item.date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !item.providerName.isEmpty {
                                    Text("·")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.providerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Text(item.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func filterButton(title: String, filter: AppState.HistoryStatus?) -> some View {
        Button(title) {
            historyFilter = filter
        }
        .buttonStyle(.bordered)
        .tint(historyFilter == filter ? .accentColor : .secondary)
        .controlSize(.small)
    }

    @ViewBuilder
    private func statusBadge(_ status: AppState.HistoryStatus) -> some View {
        switch status {
        case .registered:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)
        case .recognized:
            Image(systemName: "eye.circle.fill")
                .foregroundColor(.blue)
                .font(.body)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .font(.body)
        }
    }

    // MARK: - About Tab

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var aboutView: some View {
        Form {
            Section {
                LabeledContent(String(localized: "앱 이름", comment: "App name label")) {
                    Text("Yaksok")
                }
                LabeledContent(String(localized: "버전", comment: "Version label")) {
                    Text(appVersion)
                }
                LabeledContent(String(localized: "설명", comment: "Description label")) {
                    Text("텍스트/이미지에서 일정을 추출하여 캘린더에 등록", comment: "App description")
                }
            }

            Section(String(localized: "업데이트", comment: "Update section")) {
                HStack {
                    Button(String(localized: "업데이트 확인...", comment: "Check for updates button")) {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)

                    Toggle(String(localized: "자동 확인", comment: "Automatic update check"),
                           isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                           ))

                    Spacer()
                }
            }

            Section(String(localized: "지원 서비스", comment: "Supported services section")) {
                Text("Google Gemini, OpenAI, Anthropic Claude")
                Text("Apple Intelligence (macOS 26+)")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
