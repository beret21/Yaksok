import AppIntents
import AppKit
import Foundation

// MARK: - Shortcuts.app Integration (macOS 14+)

/// "일정 추출" action for Shortcuts.app
struct ExtractScheduleIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "일정 추출"
    nonisolated static let description: IntentDescription = "텍스트에서 일정 정보를 추출하여 캘린더에 등록합니다."
    static let openAppWhenRun: Bool = true

    @Parameter(title: "텍스트", description: "일정 정보가 포함된 텍스트")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "yaksok://extract?text=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        return .result(value: "일정 추출을 시작합니다.")
    }
}

/// "클립보드에서 일정 추출" action
struct ExtractFromClipboardIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "클립보드에서 일정 추출"
    nonisolated static let description: IntentDescription = "클립보드의 텍스트 또는 이미지에서 일정을 추출합니다."
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "yaksok://clipboard") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

/// "화면 캡처로 일정 추출" action
struct ExtractFromCaptureIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "화면 캡처로 일정 추출"
    nonisolated static let description: IntentDescription = "화면 영역을 캡처하여 일정을 추출합니다."
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "yaksok://capture") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct YaksokShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExtractScheduleIntent(),
            phrases: [
                "약속 추출해줘",
                "\(.applicationName)으로 일정 추출",
            ],
            shortTitle: "일정 추출",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: ExtractFromClipboardIntent(),
            phrases: [
                "\(.applicationName) 클립보드에서 일정",
            ],
            shortTitle: "클립보드 일정",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: ExtractFromCaptureIntent(),
            phrases: [
                "\(.applicationName) 화면 캡처 일정",
            ],
            shortTitle: "캡처 일정",
            systemImageName: "camera.viewfinder"
        )
    }
}
