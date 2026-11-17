import Foundation

/// A modifier key that can be selected as the double-tap trigger.
/// Left/right variants are not distinguished: either side counts.
public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case option
    case control
    case command
    case shift

    /// The device-independent modifier flag for this key.
    public var flag: ModifierSet {
        switch self {
        case .option: .option
        case .control: .control
        case .command: .command
        case .shift: .shift
        }
    }
}

/// Device-independent modifier flags (left/right collapsed), as produced by the event-tap adapter.
public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let control = ModifierSet(rawValue: 1 << 1)
    public static let option = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    /// Modifiers that are significant for key combos (Fn is ignored).
    public static let comboRelevant: ModifierSet = [.command, .control, .option, .shift]
    /// Modifiers that cancel a double-tap when held or changed.
    public static let tapRelevant: ModifierSet = [.command, .control, .option, .shift, .function]
}

/// A keyboard event, already converted from `CGEvent` by the adapter. Timestamps are seconds on any monotonic clock.
public enum KeyInput: Equatable, Sendable {
    /// A modifier press/release. `modifiers` is the full modifier state after the change; `keyCode` identifies
    /// the physical key (e.g. left vs right Option) and is informational only.
    case flagsChanged(modifiers: ModifierSet, keyCode: UInt16, timestamp: TimeInterval)
    case keyDown(keyCode: UInt16, modifiers: ModifierSet, isRepeat: Bool, timestamp: TimeInterval)
    case keyUp(keyCode: UInt16, modifiers: ModifierSet, timestamp: TimeInterval)
}
