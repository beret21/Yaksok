import SwiftUI
import Carbon

/// A button that records a keyboard shortcut when clicked
struct KeyRecorderView: View {
    let label: String
    @Binding var config: HotkeyConfig
    @State private var isRecording = false

    private let accentOrange = Color(red: 0.95, green: 0.45, blue: 0.25)

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .leading)

            Button(action: { isRecording = true }) {
                Text(isRecording
                     ? String(localized: "키를 입력하세요...", comment: "Recording hotkey")
                     : config.displayString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .frame(minWidth: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .foregroundColor(isRecording ? accentOrange : .primary)
            .background(
                KeyRecorderNSView(isRecording: $isRecording, config: $config)
                    .frame(width: 0, height: 0)
            )
        }
    }
}

// MARK: - NSView wrapper for key event capture

struct KeyRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var config: HotkeyConfig

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyRecorded = { keyCode, modifiers in
            config = HotkeyConfig(keyCode: UInt32(keyCode), modifiers: HotkeyConfig.carbonModifiers(from: modifiers))
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            // Become first responder to capture keys
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

// MARK: - NSView that captures keyboard events

final class KeyCaptureView: NSView {
    var isRecording = false
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        // Require at least one modifier key (Cmd, Shift, Opt, Ctrl)
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !mods.isEmpty else { return }

        // Ignore modifier-only keys
        let modOnlyKeys: Set<UInt16> = [
            UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control),
            UInt16(kVK_RightCommand), UInt16(kVK_RightShift), UInt16(kVK_RightOption), UInt16(kVK_RightControl),
        ]
        guard !modOnlyKeys.contains(event.keyCode) else { return }

        onKeyRecorded?(event.keyCode, mods)
    }
}
