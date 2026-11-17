/// Live, re-derived state of the Visor window at trigger time.
public struct VisorState: Equatable, Sendable {
    public var exists: Bool
    public var visible: Bool
    public var fullyCovered: Bool

    public init(exists: Bool, visible: Bool, fullyCovered: Bool) {
        self.exists = exists
        self.visible = visible
        self.fullyCovered = fullyCovered
    }
}

public enum ToggleAction: Equatable, Sendable {
    case create
    case show
    case hide
    case bringToFront
}

public enum ToggleDecision {
    public static func decide(_ state: VisorState) -> ToggleAction {
        guard state.exists else { return .create }
        guard state.visible else { return .show }
        return state.fullyCovered ? .bringToFront : .hide
    }
}
