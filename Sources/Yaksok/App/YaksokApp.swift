// YaksokApp.swift — macOS menu bar app
//
// Uses NSStatusItem directly (not SwiftUI MenuBarExtra) for reliable
// menu bar icon. Pattern from MacTR/MacTRApp.swift.

import AppKit
import Sparkle
import SwiftUI

// MARK: - App Entry Point

@main
struct YaksokEntry {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // No dock icon
        let delegate = StatusBarController()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - Status Bar Controller

@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let appState = AppState()
    let inputCoordinator = InputCoordinator()
    private var menuBuilder: StatusMenuBuilder!
    private let formWindow = ScheduleFormWindow()
    private let hotkeyManager = HotkeyManager()
    private var settingsWindow: NSWindow?
    private var statusPopover: NSPopover?
    private var onboardingWindow: NSWindow?

    // Sparkle auto-updater
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()
        menuBuilder = StatusMenuBuilder(appState: appState, delegate: self, updaterController: updaterController)
        setupStatusItem()
        setupGlobalHotkeys()
        registerURLHandler()
        NSApp.servicesProvider = self
        NSRegisterServicesProvider(self, "Yaksok")  // Must match NSPortName in Info.plist
        NSUpdateDynamicServices()
        Log.app.info("Yaksok started")

        // Auto-refresh model list (weekly)
        if appState.needsModelRefresh {
            Task {
                await appState.refreshModels(for: .gemini)
                await appState.refreshModels(for: .openai)
                await appState.refreshModels(for: .claude)
            }
        }

        // 삭제된 캘린더 ID 정리
        let calMgr = CalendarManager()
        calMgr.requestAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let validIDs = Set(calMgr.allCalendars().map(\.calendarIdentifier))
            self.appState.pruneConflictCalendarIDs(validIDs: validIDs)
        }

        // Show onboarding on first launch
        if OnboardingView.needsOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }

    // MARK: - URL Scheme (yaksok://extract?text=..., yaksok://clipboard, yaksok://capture)

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString)
        else { return }

        Log.debug("[URL] Received: \(urlString)")

        let host = url.host ?? ""
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "extract":
            // yaksok://extract?text=일정텍스트
            if let text = params.first(where: { $0.name == "text" })?.value, !text.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.showProcessingPopover()
                    await self.inputCoordinator.extractFromText(text, state: self.appState)
                    self.dismissProcessingPopover()
                    self.handleExtractionResult()
                }
            }
        case "clipboard":
            // yaksok://clipboard
            extractFromClipboard()
        case "capture":
            // yaksok://capture
            extractFromScreenCapture()
        case "selection":
            // yaksok://selection
            extractFromSelectedText()
        default:
            // yaksok:// (no host) — default to clipboard
            extractFromClipboard()
        }
    }

    // MARK: - Services Menu Handler

    @objc func extractFromService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "선택된 텍스트가 없습니다." as NSString
            return
        }
        Log.debug("[Services] Received text: \(text.count) chars")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showProcessingPopover()
            await self.inputCoordinator.extractFromText(text, state: self.appState)
            self.dismissProcessingPopover()
            self.handleExtractionResult()
        }
    }

    /// .accessory 모드에서는 기본 Edit 메뉴가 없어 Cmd+C/V/X/A가 동작하지 않음.
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: String(localized: "종료", comment: "Quit"),
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — enables Cmd+C/V/X/A/Z in text fields
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.clock",
                                   accessibilityDescription: "Yaksok")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        let menu = menuBuilder.buildMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Drag & Drop onto menu bar icon
        if let button = statusItem.button {
            button.window?.registerForDraggedTypes([.string, .fileURL, .tiff, .png])
            let dragDelegate = StatusBarDragDelegate { [weak self] in self }
            button.window?.delegate = dragDelegate
            self.dragDelegate = dragDelegate
        }
    }

    private var dragDelegate: StatusBarDragDelegate?

    // MARK: - Processing Status (NSPopover below menu bar icon)
    // Note: Popover requires menu bar icon to be visible.
    // If hidden by Bartender/Ice, the popover won't appear.

    func showProcessingPopover() {
        dismissProcessingPopover()

        guard let button = statusItem.button else { return }

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 220, height: 50)
        popover.contentViewController = NSHostingController(
            rootView: ProcessingStatusView(
                provider: appState.selectedProvider.displayName,
                model: appState.selectedModel.displayName
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.statusPopover = popover
    }

    func dismissProcessingPopover() {
        statusPopover?.performClose(nil)
        statusPopover = nil
    }

    // MARK: - Global Hotkeys

    func setupGlobalHotkeys() {
        hotkeyManager.unregisterAll()

        let configs = HotkeyConfig.loadAll()

        hotkeyManager.register(config: configs.clipboard, id: HotkeyManager.clipboardID) { [weak self] in
            self?.extractFromClipboard()
        }

        hotkeyManager.register(config: configs.capture, id: HotkeyManager.captureID) { [weak self] in
            self?.extractFromScreenCapture()
        }

        hotkeyManager.register(config: configs.selectedText, id: HotkeyManager.selectedTextID) { [weak self] in
            self?.extractFromSelectedText()
        }

        Log.debug("[Hotkey] Registered: clipboard=\(configs.clipboard.displayString), capture=\(configs.capture.displayString), selection=\(configs.selectedText.displayString)")
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let newMenu = menuBuilder.buildMenu()
        newMenu.delegate = self

        menu.removeAllItems()
        for item in newMenu.items {
            newMenu.removeItem(item)
            menu.addItem(item)
        }
    }

    // MARK: - Common result handler

    func handleExtractionResult() {
        if appState.showScheduleForm, let event = appState.extractedEvent {
            // Record recognized state (LLM extraction done, form shown)
            let historyID = appState.recordRecognized(
                title: event.title ?? "일정",
                date: event.startDate ?? "",
                providerName: appState.selectedProvider.displayName
            )

            formWindow.show(
                event: event,
                conflictCalendarIDs: appState.conflictCheckCalendarIDs,
                defaultDurationMinutes: appState.defaultDurationMinutes,
                providerName: appState.selectedProvider.displayName,
                onReanalyze: { [weak self] providerID in
                    guard let self, let text = self.appState.lastInputText else { return nil }
                    return try? await self.inputCoordinator.reanalyze(text: text, providerID: providerID)
                },
                onRegistered: { [weak self] title, date in
                    self?.appState.updateToRegistered(id: historyID, title: title, date: date)
                },
                onCancelled: { [weak self] in
                    self?.appState.updateToCancelled(id: historyID)
                },
                onDismiss: { [weak self] in
                    self?.appState.resetProcessingState()
                }
            )
        }

        if appState.showError, let error = appState.lastError {
            showErrorAlert(error)
            appState.resetProcessingState()
        }
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Yaksok 오류", comment: "Error alert title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "확인", comment: "OK button"))
        alert.runModal()
    }
}

// MARK: - StatusMenuDelegate

extension StatusBarController: StatusMenuDelegate {
    @objc func extractFromClipboard() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showProcessingPopover()
            await self.inputCoordinator.processClipboard(state: self.appState)
            self.dismissProcessingPopover()
            self.handleExtractionResult()
        }
    }

    @objc func extractFromScreenCapture() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showProcessingPopover()
            await self.inputCoordinator.processScreenCapture(state: self.appState)
            self.dismissProcessingPopover()
            self.handleExtractionResult()
        }
    }

    @objc func extractFromSelectedText() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.showProcessingPopover()
            await self.inputCoordinator.processSelectedText(state: self.appState)
            self.dismissProcessingPopover()
            self.handleExtractionResult()
        }
    }

    private func showOnboarding() {
        let view = OnboardingView {
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        }
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Yaksok"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.onboardingWindow = window
    }

    @objc func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appState: appState, updater: updaterController.updater) { [weak self] in
            self?.setupGlobalHotkeys()
        }
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "Yaksok 설정", comment: "Settings window title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
