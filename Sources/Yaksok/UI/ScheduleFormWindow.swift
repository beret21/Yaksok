import AppKit
import SwiftUI

/// Manages the schedule form window lifecycle
@MainActor
final class ScheduleFormWindow {
    private var window: NSWindow?

    func show(event: ScheduleEvent, conflictCalendarIDs: Set<String> = [], defaultDurationMinutes: Int = 60, providerName: String = "", onReanalyze: (@MainActor @Sendable (LLMProviderID) async -> ScheduleEvent?)? = nil, onRegistered: ((String, String) -> Void)? = nil, onCancelled: (() -> Void)? = nil, onDismiss: @escaping () -> Void) {
        window?.close()

        var view = ScheduleFormView(event: event) { [weak self] in
            self?.close()
            onDismiss()
        }
        view.onRegistered = onRegistered
        view.onCancelled = onCancelled
        view.onReanalyze = onReanalyze
        view.providerName = providerName
        view.conflictCheckCalendarIDs = conflictCalendarIDs
        view.defaultDurationMinutes = defaultDurationMinutes

        let hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = String(localized: "Yaksok 일정 등록", comment: "Window title")
        newWindow.styleMask = [.titled, .closable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.level = .floating

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak newWindow] in
            newWindow?.level = .normal
        }

        self.window = newWindow
    }

    func close() {
        window?.close()
        window = nil
    }
}
