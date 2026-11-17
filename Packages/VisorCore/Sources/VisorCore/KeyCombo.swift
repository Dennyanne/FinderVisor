import Foundation

/// A key combination: a virtual key code plus Cmd/Ctrl/Opt/Shift modifiers. Persisted as `{keyCode, modifiers}`.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierSet

    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.comboRelevant)
    }

    /// Default combo: Option+F (`kVK_ANSI_F` = 3).
    public static let defaultCombo = KeyCombo(keyCode: 3, modifiers: .option)

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifiers: try container.decode(ModifierSet.self, forKey: .modifiers)
        )
    }
}

/// What the event tap should do with an event after combo matching.
public enum ComboMatchResult: Equatable, Sendable {
    /// Deliver the event unchanged.
    case passThrough
    /// Swallow the event and trigger the toggle.
    case fire
    /// Swallow the event without triggering (autorepeat / keyUp of a matched combo).
    case swallow
}

/// Matches keyDown events against the configured combo and tracks the swallowed key so its autorepeats and keyUp
/// are consumed too. `combo == nil` never matches.
public struct ComboMatcher: Sendable {
    public var combo: KeyCombo?
    private var swallowedKeyCode: UInt16?

    public init(combo: KeyCombo?) {
        self.combo = combo
    }

    public mutating func process(_ input: KeyInput) -> ComboMatchResult {
        switch input {
        case .flagsChanged:
            return .passThrough
        case let .keyUp(keyCode, _, _):
            if keyCode == swallowedKeyCode {
                swallowedKeyCode = nil
                return .swallow
            }
            return .passThrough
        case let .keyDown(keyCode, modifiers, isRepeat, _):
            if isRepeat, keyCode == swallowedKeyCode {
                return .swallow
            }
            guard let combo, combo.keyCode == keyCode,
                  modifiers.intersection(.comboRelevant) == combo.modifiers else {
                return .passThrough
            }
            // An autorepeat whose initial press was not swallowed (e.g. F held, then Option pressed) belongs to the
            // frontmost app: let it and its keyUp through.
            guard !isRepeat else { return .passThrough }
            swallowedKeyCode = keyCode
            return .fire
        }
    }
}
