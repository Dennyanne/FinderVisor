// KeyRecorderField — records the toggle key combo (AC-H3, AC-H4).
//
// Public API:
//   struct KeyRecorderField: View {
//       init(combo: Binding<KeyCombo?>, onRecordingChanged: @escaping (Bool) -> Void = { _ in })
//   }
//   extension KeyCombo { var displayString: String }   // e.g. "⌥F", using the current keyboard layout
// Click to record; the next key press with at least one of ⌘/⌃/⌥ (or any F-key) becomes the combo. Esc cancels,
// Delete clears. `onRecordingChanged(true/false)` lets the caller suspend the global event tap while recording.

import AppKit
import Carbon.HIToolbox
import SwiftUI
import VisorCore

struct KeyRecorderField: View {
    @Binding var combo: KeyCombo?
    var onRecordingChanged: (Bool) -> Void = { _ in }

    @State private var recorder = ComboRecorder()

    init(combo: Binding<KeyCombo?>, onRecordingChanged: @escaping (Bool) -> Void = { _ in }) {
        _combo = combo
        self.onRecordingChanged = onRecordingChanged
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .frame(minWidth: 120)
                    .foregroundStyle(recorder.isRecording || combo == nil ? .secondary : .primary)
            }
            .help(recorder.isRecording ? "Press a key combination. Esc cancels, Delete clears." : "Click to record")
            Button {
                stopRecording()
                combo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(combo == nil)
            .help("Clear shortcut")
            .accessibilityLabel("Clear shortcut")
        }
        .onDisappear(perform: stopRecording)
        // The Settings window is AppKit-hosted and kept alive when closed, so onDisappear alone is not enough:
        // stop when any window closes or loses key (the local monitor no longer sees keys then) so the global
        // hotkeys can never stay suspended.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stopRecording() }
    }

    private var label: String {
        if recorder.isRecording {
            return recorder.heldModifiers.isEmpty ? "Type shortcut…" : recorder.heldModifiers.glyphs + "…"
        }
        return combo?.displayString ?? "None"
    }

    private func toggleRecording() {
        if recorder.isRecording {
            stopRecording()
        } else {
            onRecordingChanged(true)
            recorder.start { outcome in
                switch outcome {
                case let .recorded(newCombo): combo = newCombo
                case .cleared: combo = nil
                case .cancelled: break
                }
                onRecordingChanged(false)
            }
        }
    }

    private func stopRecording() {
        guard recorder.isRecording else { return }
        recorder.stop()
        onRecordingChanged(false)
    }
}

// MARK: - Recorder

@MainActor
@Observable
private final class ComboRecorder {
    enum Outcome {
        case recorded(KeyCombo)
        case cleared
        case cancelled
    }

    private(set) var isRecording = false
    private(set) var heldModifiers: ModifierSet = []
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var completion: ((Outcome) -> Void)?

    func start(completion: @escaping (Outcome) -> Void) {
        stop()
        self.completion = completion
        isRecording = true
        heldModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        completion = nil
        isRecording = false
        heldModifiers = []
    }

    private func handle(_ event: NSEvent) {
        let modifiers = ModifierSet(event.modifierFlags).intersection(.comboRelevant)
        if event.type == .flagsChanged {
            heldModifiers = modifiers
            return
        }
        let keyCode = event.keyCode
        if modifiers.isEmpty, Int(keyCode) == kVK_Escape {
            finish(.cancelled)
        } else if modifiers.isEmpty, Int(keyCode) == kVK_Delete || Int(keyCode) == kVK_ForwardDelete {
            finish(.cleared)
        } else if !modifiers.intersection([.command, .control, .option]).isEmpty || KeyCombo.isFunctionKey(keyCode) {
            finish(.recorded(KeyCombo(keyCode: keyCode, modifiers: modifiers)))
        } else {
            NSSound.beep()
        }
    }

    private func finish(_ outcome: Outcome) {
        let completion = self.completion
        stop()
        completion?(outcome)
    }
}

// MARK: - Display

private extension ModifierSet {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
    }

    /// Standard macOS order: ⌃⌥⇧⌘.
    var glyphs: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

extension KeyCombo {
    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeys[Int(keyCode)] != nil
    }

    /// Modifier glyphs plus the key as produced by the current keyboard layout (e.g. "⌥F").
    var displayString: String {
        modifiers.glyphs + Self.keyName(keyCode)
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        if let name = functionKeys[Int(keyCode)] ?? specialKeys[Int(keyCode)] { return name }
        if let translated = translate(keyCode), !translated.isEmpty { return translated.uppercased() }
        return "Key \(keyCode)"
    }

    /// Character the key produces without modifiers on the current (ASCII-capable) layout, via UCKeyTranslate.
    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
