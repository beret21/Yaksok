import AppKit
import ApplicationServices

/// Reads selected text from the frontmost application
/// Uses Accessibility API (AXUIElement) with Cmd+C fallback
@MainActor
final class SelectedTextReader {

    /// Read selected text from the currently focused app
    func readSelectedText() async -> String? {
        // Try AXUIElement first
        if let text = readViaAccessibility() {
            Log.input.info("Selected text via AX: \(text.count) chars")
            return text
        }

        // Fallback: simulate Cmd+C and read clipboard
        Log.input.info("AX failed, falling back to Cmd+C")
        return await readViaCmdC()
    }

    // MARK: - Accessibility API

    private func readViaAccessibility() -> String? {
        let systemElement = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success
        else { return nil }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success
        else { return nil }

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success
        else { return nil }

        let text = selectedText as? String
        return text?.isEmpty == true ? nil : text
    }

    // MARK: - Cmd+C Fallback

    private func readViaCmdC() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)  // 'c'
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Wait for clipboard to update
        try? await Task.sleep(for: .milliseconds(200))

        // Check if clipboard changed
        guard pasteboard.changeCount != savedChangeCount else {
            Log.input.info("Cmd+C: clipboard unchanged")
            return nil
        }

        let text = pasteboard.string(forType: .string)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : text
    }
}
