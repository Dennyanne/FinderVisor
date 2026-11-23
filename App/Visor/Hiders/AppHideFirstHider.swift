import ApplicationServices
import VisorCore

/// How a hide was carried out (focus return differs).
enum HideMethod {
    case appHide
    case minimize
}

/// Hides / shows the Visor window. Only the Visor's own AX element is ever minimized or un-minimized.
@MainActor
protocol VisorHiding {
    /// Re-derived from live state, never cached.
    func isHidden(_ visor: AXUIElement) -> Bool
    func hide(_ visor: ResolvedVisor, returnsFocusToFinder: Bool) -> HideMethod
    /// Normalizes every hidden state: unhides Finder if hidden, un-minimizes the Visor if minimized.
    func unhide(_ visor: AXUIElement)
}

/// App-hide first, minimize fallback. When the Visor's tab group is Finder's only visible window
/// (`AppHideDecision`), hide = `NSRunningApplication.hide()` on Finder (instant); otherwise `AXMinimized = true`
/// (~0.5 s animation; minimizing the selected tab's window minimizes the whole tab group). A user Cmd-M or Cmd-H
/// counts as hidden too.
final class AppHideFirstHider: VisorHiding {
    private let ax: AXWindowService
    private let activator: AppActivator
    private let windowList: WindowListProvider

    init(ax: AXWindowService, activator: AppActivator, windowList: WindowListProvider) {
        self.ax = ax
        self.activator = activator
        self.windowList = windowList
    }

    func isHidden(_ visor: AXUIElement) -> Bool {
        activator.isFinderHidden || ax.isMinimized(visor) == true
    }

    func hide(_ visor: ResolvedVisor, returnsFocusToFinder: Bool) -> HideMethod {
        if let pid = activator.finderPID, canHideFinder(pid: pid, visor: visor, returnsFocusToFinder: returnsFocusToFinder) {
            activator.hideFinder()
            return .appHide
        }
        ax.setMinimized(visor.element, true)
        return .minimize
    }

    func unhide(_ visor: AXUIElement) {
        if activator.isFinderHidden { activator.unhideFinder() }
        if ax.isMinimized(visor) == true { ax.setMinimized(visor, false) }
    }

    /// Minimized frames come from AX and are read only when the window list alone does not allow app-hide.
    private func canHideFinder(pid: pid_t, visor: ResolvedVisor, returnsFocusToFinder: Bool) -> Bool {
        let windows = windowList.windows(ofPID: pid)
        func decide(_ minimizedFrames: [CGRect]) -> Bool {
            AppHideDecision.canHideFinder(finderWindows: windows, visorIDs: visor.memberIDs,
                                          minimizedFrames: minimizedFrames, returnsFocusToFinder: returnsFocusToFinder)
        }
        return decide([]) || decide(minimizedFrames(pid: pid))
    }

    private func minimizedFrames(pid: pid_t) -> [CGRect] {
        ax.windows(ofApp: pid).filter { ax.isMinimized($0) == true }.compactMap { ax.frame(of: $0) }
    }
}
