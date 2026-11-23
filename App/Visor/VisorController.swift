import AppKit
import OSLog
import VisorCore

/// Orchestrates a toggle: re-derive live state → `ToggleDecision` → create / show / hide / bring to front.
/// Only the Visor's own AX element is ever moved, resized or minimized; Finder as a whole is hidden only when the
/// Visor is its only visible window (`AppHideFirstHider`).
@MainActor
final class VisorController {
    private static let targetRefreshInterval: Duration = .seconds(5)
    /// Caps for the show path after Finder app-hide (the spike saw the Visor miss key status in 10/30 shows).
    private static let onscreenWaitCap: Duration = .milliseconds(300)
    private static let focusRetryCap: Duration = .milliseconds(300)
    private static let pollInterval: Duration = .milliseconds(20)
    private static let focusRetryInterval: Duration = .milliseconds(40)
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
            case .show: await show(visor)
            case .hide: await hide(visor)
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
        await present(visor, at: frame)
    }

    /// Show path: normalize every hidden state (Finder hidden, minimized), then frame, raise, focus.
    private func show(_ visor: ResolvedVisor) async {
        focus.recordAtShowTime()
        guard let frame = targetFrame() else { return }
        await present(visor, at: frame)
    }

    private func present(_ visor: ResolvedVisor, at frame: CGRect) async {
        let finderWasHidden = activator.isFinderHidden
        hider.unhide(visor.element)
        ax.setFrame(visor.element, frame)
        locator.noteFrame(frame)
        locator.refreshTarget(of: visor)
        startTargetRefresh()
        guard let pid = activator.finderPID else { return }
        if finderWasHidden { await waitUntilOnscreen(visor, pid: pid) }
        await focusVisor(visor, pid: pid)
    }

    /// After `unhide()` Finder brings its windows back asynchronously; raising before the Visor is on screen can
    /// leave another window key. Polls CGWindowList (async, capped).
    private func waitUntilOnscreen(_ visor: ResolvedVisor, pid: pid_t) async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.onscreenWaitCap
        while clock.now < deadline {
            if windowList.windows(ofPID: pid).contains(where: { visor.memberIDs.contains($0.id) && $0.isOnscreen }) {
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
        logger.notice("Visor not on screen \(Self.onscreenWaitCap) after unhiding Finder")
    }

    /// AXRaise + AXMain + activate Finder, then verify Finder is frontmost with the Visor as its focused window;
    /// retried at short intervals up to a cap.
    private func focusVisor(_ visor: ResolvedVisor, pid: pid_t) async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.focusRetryCap
        repeat {
            ax.raise(visor.element)
            activator.activate(pid: pid)
            try? await Task.sleep(for: Self.focusRetryInterval)
            if activator.frontmostApplication?.pid == pid, let focused = ax.focusedWindow(ofApp: pid),
               CFEqual(focused, visor.element) {
                return
            }
        } while clock.now < deadline
        logger.notice("Visor did not become Finder's focused window within \(Self.focusRetryCap)")
    }

    private func hide(_ visor: ResolvedVisor) async {
        if let live = ax.frame(of: visor.element) { locator.noteFrame(live) }
        locator.refreshTarget(of: visor)
        stopTargetRefresh()
        switch hider.hide(visor, returnsFocusToFinder: focus.returnsToFinder) {
        case .minimize: focus.returnFocus()
        case .appHide: await focus.returnFocusAfterAppHide()
        }
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
