/// An application activation observed via `NSWorkspace.didActivateApplicationNotification`.
public struct ActivationEvent: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?
    /// True when the activated app is Finder and the Visor is Finder's key window.
    public var visorIsFinderKeyWindow: Bool

    public init(pid: Int32, bundleID: String?, visorIsFinderKeyWindow: Bool = false) {
        self.pid = pid
        self.bundleID = bundleID
        self.visorIsFinderKeyWindow = visorIsFinderKeyWindow
    }
}

/// The app to give focus back to after hiding the Visor. (For Finder, the app layer also remembers the focused
/// window's AX element, which has no value-type identity.)
public struct ReturnTarget: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String?

    public init(pid: Int32, bundleID: String?) {
        self.pid = pid
        self.bundleID = bundleID
    }
}

/// Decides which activation events update the focus-return target: FinderVisor itself is ignored; Finder is
/// ignored while the Visor is its key window; everything else becomes the new target.
public struct FocusReturnPolicy: Sendable {
    public static let finderBundleID = "com.apple.finder"
    public var ownPID: Int32

    public init(ownPID: Int32) {
        self.ownPID = ownPID
    }

    /// The new return target for `event`, or `nil` if the event must not change the current target.
    public func returnTarget(for event: ActivationEvent) -> ReturnTarget? {
        if event.pid == ownPID { return nil }
        if event.bundleID == Self.finderBundleID && event.visorIsFinderKeyWindow { return nil }
        return ReturnTarget(pid: event.pid, bundleID: event.bundleID)
    }
}
