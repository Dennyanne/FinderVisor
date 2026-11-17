import AppKit
import OSLog
import VisorCore

/// Orchestrates a toggle: re-derive live state → `ToggleDecision` → create / show / hide / bring to front.
/// Only the Visor's own AX element is ever moved, resized or minimized.
@MainActor
final class VisorController {
    private static let targetRefreshInterval: Duration = .seconds(5)
    private let logger = Logger(subsystem: "io.github.findervisor.FinderVisor", category: "visor")

    private let locator: VisorWindowLocator
    private let ax: AXWindowService
    private let windowList: WindowListProvider
    private let screens: ScreenProvider
    private let activator: AppActivator
    private let hider: VisorHiding
    private let focus: FocusReturnTracker
    private let heightPercent: () -> Int
    private var isToggling = false
    private var targetRefreshTask: Task<Void, Never>?

    /// Called when a toggle fails (e.g. Automation → Finder denied).
    var onError: ((Error) -> Void)?

    init(locator: VisorWindowLocator, ax: AXWindowService, windowList: WindowListProvider, screens: ScreenProvider,
         activator: AppActivator, hider: VisorHiding, focus: FocusReturnTracker,
         heightPercent: @escaping () -> Int) {
        self.locator = locator
        self.ax = ax
        self.windowList = windowList
        self.screens = screens
        self.activator = activator
        self.hider = hider
        self.focus = focus
        self.heightPercent = heightPercent
    }

    func toggle() async {
        guard !isToggling else { return }
        isToggling = true
        defer { isToggling = false }
        do {
            // `ToggleDecision` yields `.create` exactly when the Visor does not exist.
            guard let visor = await locator.resolve() else {
                logger.debug("toggle → create")
                try await create()
                return
            }
            let action = ToggleDecision.decide(state(of: visor))
            logger.debug("toggle → \(String(describing: action))")
            switch action {
            case .create: try await create()
            case .show: show(visor)
            case .hide: hide(visor)
            case .bringToFront: bringToFront(visor)
            }
        } catch {
            logger.error("toggle failed: \(String(describing: error))")
            onError?(error)
        }
    }

    // MARK: - State

    private func state(of visor: ResolvedVisor) -> VisorState {
        guard let activeID = visor.activeID, !hider.isHidden(visor.element), !activator.isFinderHidden else {
            return VisorState(exists: true, visible: false, fullyCovered: false)
        }
        let covered = CoverageCalculator.isFullyCovered(
            visorRect: visor.frame,
            windowsAbove: windowList.windowsAbove(activeID),
            visorWindowID: activeID,
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        return VisorState(exists: true, visible: true, fullyCovered: covered)
    }

    // MARK: - Actions

    private func create() async throws {
        focus.recordAtShowTime()
        guard let frame = targetFrame() else { return }
        let visor = try await locator.create(frame: frame)
        present(visor, at: frame)
    }

    /// Show path: normalize every hidden state (Finder hidden, minimized), then frame, raise, focus.
    private func show(_ visor: ResolvedVisor) {
        focus.recordAtShowTime()
        guard let frame = targetFrame() else { return }
        present(visor, at: frame)
    }

    private func present(_ visor: ResolvedVisor, at frame: CGRect) {
        if activator.isFinderHidden { activator.unhideFinder() }
        hider.unhide(visor.element)
        ax.setFrame(visor.element, frame)
        ax.raise(visor.element)
        if let pid = activator.finderPID { activator.activate(pid: pid) }
        locator.noteFrame(frame)
        locator.refreshTarget(of: visor)
        startTargetRefresh()
    }

    private func hide(_ visor: ResolvedVisor) {
        if let live = ax.frame(of: visor.element) { locator.noteFrame(live) }
        locator.refreshTarget(of: visor)
        stopTargetRefresh()
        hider.hide(visor.element)
        focus.returnFocus()
    }

    private func bringToFront(_ visor: ResolvedVisor) {
        focus.recordAtShowTime()
        ax.raise(visor.element)
        if let pid = activator.finderPID { activator.activate(pid: pid) }
    }

    private func targetFrame() -> CGRect? {
        VisorFrameCalculator.visorFrame(
            screens: screens.screens,
            primaryScreenHeight: screens.primaryScreenHeight,
            mouse: screens.mouseLocation,
            heightPercent: heightPercent()
        )
    }

    // MARK: - Background target refresh (re-attach tie-breaker)

    private func startTargetRefresh() {
        stopTargetRefresh()
        targetRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.targetRefreshInterval)
                guard !Task.isCancelled else { return }
                self?.locator.refreshTargetIfShown()
            }
        }
    }

    private func stopTargetRefresh() {
        targetRefreshTask?.cancel()
        targetRefreshTask = nil
    }
}
