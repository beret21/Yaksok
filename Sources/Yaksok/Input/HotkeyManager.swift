import AppKit
import Carbon

// MARK: - Hotkey Configuration (Codable, UserDefaults)

struct HotkeyConfig: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Human-readable display string (e.g., "⌘⇧E")
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    /// Convert Carbon modifiers from NSEvent modifierFlags
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// Key name from virtual keyCode
    static func keyName(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫",
        ]
        return map[keyCode] ?? "(\(keyCode))"
    }

    // MARK: - Defaults

    static let defaultClipboard = HotkeyConfig(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultCapture = HotkeyConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey | optionKey))
    static let defaultSelectedText = HotkeyConfig(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))

    // MARK: - UserDefaults persistence

    private static let clipboardKey = "hotkey_clipboard"
    private static let captureKey = "hotkey_capture"
    private static let selectedTextKey = "hotkey_selectedText"

    static func loadAll() -> (clipboard: HotkeyConfig, capture: HotkeyConfig, selectedText: HotkeyConfig) {
        (
            load(key: clipboardKey) ?? defaultClipboard,
            load(key: captureKey) ?? defaultCapture,
            load(key: selectedTextKey) ?? defaultSelectedText
        )
    }

    static func saveAll(clipboard: HotkeyConfig, capture: HotkeyConfig, selectedText: HotkeyConfig) {
        save(clipboard, key: clipboardKey)
        save(capture, key: captureKey)
        save(selectedText, key: selectedTextKey)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: clipboardKey)
        UserDefaults.standard.removeObject(forKey: captureKey)
        UserDefaults.standard.removeObject(forKey: selectedTextKey)
    }

    private static func load(key: String) -> HotkeyConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyConfig.self, from: data)
    }

    private static func save(_ config: HotkeyConfig, key: String) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Hotkey Manager

/// Global hotkey manager using Carbon API (RegisterEventHotKey)
@MainActor
final class HotkeyManager {

    private var hotkeyRefs: [UInt32: EventHotKeyRef?] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandlerInstalled = false

    // Hotkey IDs
    static let clipboardID: UInt32 = 1
    static let captureID: UInt32 = 2
    static let selectedTextID: UInt32 = 3

    // MARK: - Registration

    @discardableResult
    func register(config: HotkeyConfig, id: UInt32, handler: @escaping @MainActor () -> Void) -> Bool {
        // Unregister existing if any
        if let ref = hotkeyRefs[id], let r = ref {
            UnregisterEventHotKey(r)
            hotkeyRefs.removeValue(forKey: id)
        }

        if !eventHandlerInstalled {
            installEventHandler()
            eventHandlerInstalled = true
        }

        var hotkeyID = EventHotKeyID(
            signature: OSType(0x594B_534B), // "YKSK"
            id: id
        )

        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr else {
            Log.debug("[Hotkey] Failed to register id=\(id) \(config.displayString): \(status)")
            return false
        }

        hotkeyRefs[id] = hotkeyRef
        handlers[id] = handler
        Log.debug("[Hotkey] Registered id=\(id) \(config.displayString)")
        return true
    }

    func unregisterAll() {
        for (_, ref) in hotkeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotkeyRefs.removeAll()
        handlers.removeAll()
    }

    // MARK: - Event Handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard status == noErr else { return status }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()

                DispatchQueue.main.async {
                    manager.handlers[hotkeyID.id]?()
                }

                return noErr
            },
            1,
            &eventType,
            selfPtr,
            nil
        )
    }
}
