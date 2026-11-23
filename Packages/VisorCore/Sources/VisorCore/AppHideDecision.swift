import CoreGraphics

/// Decides whether hiding the Visor may hide the whole Finder app (instant) instead of minimizing it (~0.5 s).
///
/// App-hide is allowed only when the Visor's tab group is Finder's only visible window, so no other Finder window
/// disappears with it. Every other Finder window counts as visible unless it is:
/// - one of the Visor's own tab windows (`visorIDs`);
/// - smaller than 200x150 pt (Finder's layer-0 helper windows, measured as four 1512x33 strips and one 64x64 window);
/// - off screen and at the frame of a minimized Finder window (minimized, including that group's inactive tabs).
///
/// An off-screen window that matches no minimized frame is on another Space and blocks app-hide. App-hide is also
/// refused when focus returns to Finder itself, because activating a hidden Finder would unhide it (and the Visor).
/// `finderWindows` are Finder's layer-0, non-transparent windows on all Spaces (the desktop is not layer 0).
public enum AppHideDecision {
    public static let minimumWindowSize = CGSize(width: 200, height: 150)
    public static let frameTolerance: CGFloat = 2

    public static func canHideFinder(
        finderWindows: [ListedWindow],
        visorIDs: Set<UInt32>,
        minimizedFrames: [CGRect],
        returnsFocusToFinder: Bool
    ) -> Bool {
        guard !returnsFocusToFinder else { return false }
        return !finderWindows.contains { window in
            guard !visorIDs.contains(window.id),
                  window.bounds.width >= minimumWindowSize.width,
                  window.bounds.height >= minimumWindowSize.height else { return false }
            if window.isOnscreen { return true }
            return !minimizedFrames.contains { window.bounds.isApproximately($0, tolerance: frameTolerance) }
        }
    }
}
