import AppKit
import Sparkle

/// Builds the NSMenu for the status bar item
@MainActor
final class StatusMenuBuilder {
    private weak var appState: AppState?
    private weak var delegate: StatusMenuDelegate?
    private let updaterController: SPUStandardUpdaterController

    init(appState: AppState, delegate: StatusMenuDelegate, updaterController: SPUStandardUpdaterController) {
        self.appState = appState
        self.delegate = delegate
        self.updaterController = updaterController
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Version / Provider / Model info
        if let state = appState {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let providerItem = NSMenuItem(
                title: "v\(version) / \(state.selectedProvider.displayName) / \(state.selectedModel.displayName)",
                action: nil,
                keyEquivalent: ""
            )
            providerItem.isEnabled = false
            menu.addItem(providerItem)
            menu.addItem(.separator())
        }

        // Method 1: Clipboard extraction
        let clipboardItem = NSMenuItem(
            title: String(localized: "클립보드에서 일정 추출", comment: "Extract from clipboard"),
            action: #selector(StatusMenuDelegate.extractFromClipboard),
            keyEquivalent: ""
        )
        clipboardItem.target = delegate
        menu.addItem(clipboardItem)

        // Method 2: Screen capture
        let captureItem = NSMenuItem(
            title: String(localized: "화면 캡처로 일정 추출", comment: "Extract from screen capture"),
            action: #selector(StatusMenuDelegate.extractFromScreenCapture),
            keyEquivalent: ""
        )
        captureItem.target = delegate
        menu.addItem(captureItem)

        // Method 3: Selected text
        let selectedItem = NSMenuItem(
            title: String(localized: "선택 텍스트에서 일정 추출", comment: "Extract from selected text"),
            action: #selector(StatusMenuDelegate.extractFromSelectedText),
            keyEquivalent: ""
        )
        selectedItem.target = delegate
        menu.addItem(selectedItem)

        // Processing indicator
        if let state = appState, state.isProcessing {
            menu.addItem(.separator())
            let processingItem = NSMenuItem(
                title: String(localized: "처리 중...", comment: "Processing indicator"),
                action: nil,
                keyEquivalent: ""
            )
            processingItem.isEnabled = false
            menu.addItem(processingItem)
        }

        // Recent history (registered only)
        if let state = appState, !state.registeredHistory.isEmpty {
            menu.addItem(.separator())
            let historyHeader = NSMenuItem(
                title: String(localized: "최근 등록", comment: "Recent history header"),
                action: nil, keyEquivalent: ""
            )
            historyHeader.isEnabled = false
            menu.addItem(historyHeader)

            for item in state.registeredHistory {
                let histItem = NSMenuItem(
                    title: "  \(item.title) (\(item.date))",
                    action: nil, keyEquivalent: ""
                )
                histItem.isEnabled = false
                menu.addItem(histItem)
            }
        }

        menu.addItem(.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: String(localized: "설정...", comment: "Settings menu"),
            action: #selector(StatusMenuDelegate.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = delegate
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(
            title: String(localized: "업데이트 확인...", comment: "Check for updates menu"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: "u"
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: String(localized: "종료", comment: "Quit menu"),
            action: #selector(StatusMenuDelegate.quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = delegate
        menu.addItem(quitItem)

        return menu
    }
}

// MARK: - Delegate Protocol

@MainActor
@objc protocol StatusMenuDelegate: AnyObject {
    func extractFromClipboard()
    func extractFromScreenCapture()
    func extractFromSelectedText()
    func openSettings()
    func quitApp()
}
