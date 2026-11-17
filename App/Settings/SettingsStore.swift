// SettingsStore — persisted user settings (AC-S3) that push hotkey bindings into the event tap synchronously (AC-H5).
//
// Public API (main actor, @Observable):
//   init(defaults: UserDefaults = .standard, hotkeys: EventTapHotkeySource?)
//   var doubleTapModifier: ModifierKey?   // nil = Off
//   var combo: KeyCombo?                  // nil = cleared
//   var heightPercent: Int                // always validated to 20...90, step 5
//   var settings: VisorSettings { get }   // snapshot of the three values
//   var isRecordingCombo: Bool            // set by the combo recorder; suspends the global tap while true
// Launch at Login is not stored here; it is read from SMAppService (see LoginItemService).
// Persistence: one UserDefaults key, "visorSettings", holding JSON-encoded VisorSettings (missing fields → defaults).

import Foundation
import Observation
import VisorCore

@MainActor
@Observable
final class SettingsStore {
    static let defaultsKey = "visorSettings"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let hotkeys: EventTapHotkeySource?

    var doubleTapModifier: ModifierKey? {
        didSet { persistAndPush() }
    }

    var combo: KeyCombo? {
        didSet { persistAndPush() }
    }

    var heightPercent: Int {
        didSet {
            // Assigning inside didSet does not re-enter didSet.
            let valid = VisorSettings.validatedHeightPercent(heightPercent)
            if valid != heightPercent { heightPercent = valid }
            persistAndPush()
        }
    }

    var isRecordingCombo = false {
        didSet { hotkeys?.isSuspended = isRecordingCombo }
    }

    var settings: VisorSettings {
        VisorSettings(doubleTapModifier: doubleTapModifier, combo: combo, heightPercent: heightPercent)
    }

    init(defaults: UserDefaults = .standard, hotkeys: EventTapHotkeySource?) {
        self.defaults = defaults
        self.hotkeys = hotkeys
        let loaded = Self.load(from: defaults)
        self.doubleTapModifier = loaded.doubleTapModifier
        self.combo = loaded.combo
        self.heightPercent = loaded.heightPercent
        hotkeys?.setBindings(doubleTapModifier: loaded.doubleTapModifier, combo: loaded.combo)
    }

    private static func load(from defaults: UserDefaults) -> VisorSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(VisorSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    private func persistAndPush() {
        let snapshot = settings
        hotkeys?.setBindings(doubleTapModifier: snapshot.doubleTapModifier, combo: snapshot.combo)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
