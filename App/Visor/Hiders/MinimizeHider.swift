import ApplicationServices

/// Hides / shows the Visor window. Only the Visor's own AX element is ever passed in.
@MainActor
protocol VisorHiding {
    /// Re-derived from live state, never cached.
    func isHidden(_ visor: AXUIElement) -> Bool
    func hide(_ visor: AXUIElement)
    func unhide(_ visor: AXUIElement)
}

/// P3 (spike decision): hide = `AXMinimized = true`. A user Cmd-M counts as hidden too. Minimizing the selected
/// tab's window minimizes the whole tab group.
final class MinimizeHider: VisorHiding {
    private let ax: AXWindowService

    init(ax: AXWindowService) {
        self.ax = ax
    }

    func isHidden(_ visor: AXUIElement) -> Bool {
        ax.isMinimized(visor) == true
    }

    func hide(_ visor: AXUIElement) {
        ax.setMinimized(visor, true)
    }

    func unhide(_ visor: AXUIElement) {
        if ax.isMinimized(visor) == true { ax.setMinimized(visor, false) }
    }
}
