import Foundation

/// Detects a double tap of a single modifier key.
///
/// A *tap* is: the target modifier goes down while no other of {Cmd, Ctrl, Opt, Shift, Fn} is held, then goes up
/// within `maxTapHold`, with no keyDown and no other modifier change in between. The detector fires on the second
/// tap's release if the second press began at most `maxGap` after the first release. Any keyDown or other-modifier
/// change resets. It fires at most once per pair. `modifier == nil` (Off) never fires.
public struct DoubleTapDetector: Sendable {
    public var modifier: ModifierKey? {
        didSet { if modifier != oldValue { reset() } }
    }
    public let maxTapHold: TimeInterval
    public let maxGap: TimeInterval

    private enum Phase: Equatable {
        case idle
        case firstDown(at: TimeInterval)
        case firstUp(at: TimeInterval)
        case secondDown(at: TimeInterval)
    }

    private var phase: Phase = .idle
    private var lastModifiers: ModifierSet = []

    public init(modifier: ModifierKey?, maxTapHold: TimeInterval = 0.25, maxGap: TimeInterval = 0.30) {
        self.modifier = modifier
        self.maxTapHold = maxTapHold
        self.maxGap = maxGap
    }

    public mutating func reset() {
        phase = .idle
    }

    /// Feeds one event; returns `true` when a double tap completes on this event.
    public mutating func process(_ input: KeyInput) -> Bool {
        switch input {
        case .keyDown:
            phase = .idle
            return false
        case .keyUp:
            return false
        case let .flagsChanged(modifiers, _, timestamp):
            let current = modifiers.intersection(.tapRelevant)
            let previous = lastModifiers
            lastModifiers = current
            guard let modifier else {
                phase = .idle
                return false
            }
            let target = modifier.flag
            let others = current.subtracting(target)
            let othersChanged = !current.symmetricDifference(previous).subtracting(target).isEmpty
            if othersChanged || !others.isEmpty {
                phase = .idle
                return false
            }
            return advance(targetDown: current.contains(target), at: timestamp)
        }
    }

    private mutating func advance(targetDown: Bool, at time: TimeInterval) -> Bool {
        switch (phase, targetDown) {
        case (.idle, true):
            phase = .firstDown(at: time)
        case let (.firstDown(start), false):
            phase = time - start <= maxTapHold ? .firstUp(at: time) : .idle
        case let (.firstUp(release), true):
            phase = time - release <= maxGap ? .secondDown(at: time) : .firstDown(at: time)
        case let (.secondDown(start), false):
            phase = .idle
            return time - start <= maxTapHold
        default:
            // Same-state repeats (e.g. the other side of the same modifier) change nothing.
            break
        }
        return false
    }
}
