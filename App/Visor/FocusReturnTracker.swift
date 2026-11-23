import AppKit
import VisorCore

/// Remembers which app (and, for Finder, which window) to give focus back to when the Visor hides.
///
/// Updated continuously from `didActivateApplicationNotification` through `FocusReturnPolicy`, and snapshotted at
/// show time before Finder is activated. Finder activations right after a show are ignored so the Visor's own
/// activation (whose AX focus may still point at another Finder window) cannot replace the target.
@MainActor
final class FocusReturnTracker {
    private static let showSettleInterval: Duration = .seconds(1)
    private static let appHideSettleCap: Duration = .milliseconds(300)
    private static let appHidePollInterval: Duration = .milliseconds(20)
    private static let appHideRetryInterval: Duration = .milliseconds(50)

    private let policy: FocusReturnPolicy
    private let ax: AXWindowService
    private let activator: AppActivator
    private let isVisorWindow: (AXUIElement) -> Bool
    private var target: ReturnTarget?
    /// Finder's focused (non-Visor) window when `target` is Finder; the only non-Visor window ever touched (raised).
    private var finderWindow: AXUIElement?
    private var ignoreFinderUntil: ContinuousClock.Instant?
    private var token: NSObjectProtocol?

    init(ax: AXWindowService, activator: AppActivator, isVisorWindow: @escaping (AXUIElement) -> Bool) {
        policy = FocusReturnPolicy(ownPID: ProcessInfo.processInfo.processIdentifier)
        self.ax = ax
        self.activator = activator
        self.isVisorWindow = isVisorWindow
    }

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier
            MainActor.assumeIsolated { self?.record(pid: pid, bundleID: bundleID) }
        }
    }

    /// Snapshot the frontmost app before the Visor is shown or brought to front.
    func recordAtShowTime() {
        if let front = activator.frontmostApplication {
            record(pid: front.pid, bundleID: front.bundleID)
        }
        ignoreFinderUntil = ContinuousClock.now + Self.showSettleInterval
    }

    /// Whether focus goes back to Finder; then Finder must not be app-hidden (activating it would unhide it).
    var returnsToFinder: Bool {
        target?.bundleID == FocusReturnPolicy.finderBundleID
    }

    /// Focus return after Finder app-hide: macOS activates an app of its own choosing once Finder hides, which can
    /// land after (and override) an immediate activation. Waits until Finder is no longer frontmost, then activates
    /// the target captured before the hide, re-activating it until it is frontmost (each phase capped).
    func returnFocusAfterAppHide() async {
        guard let target else { return }
        let clock = ContinuousClock()
        var deadline = clock.now + Self.appHideSettleCap
        while let finder = activator.finderPID, activator.frontmostApplication?.pid == finder, clock.now < deadline {
            try? await Task.sleep(for: Self.appHidePollInterval)
        }
        deadline = clock.now + Self.appHideSettleCap
        repeat {
            guard activator.activate(pid: target.pid) else {
                if self.target == target {
                    self.target = nil
                    finderWindow = nil
                }
                return
            }
            try? await Task.sleep(for: Self.appHideRetryInterval)
            if activator.frontmostApplication?.pid == target.pid { return }
        } while clock.now < deadline
    }

    /// Activates the return target after a hide; if it is Finder, re-raises its remembered (non-Visor) window.
    func returnFocus() {
        guard let target else { return }
        guard activator.activate(pid: target.pid) else {
            self.target = nil
            finderWindow = nil
            return
        }
        if target.bundleID == FocusReturnPolicy.finderBundleID, let window = finderWindow,
           ax.isValid(window), !isVisorWindow(window) {
            ax.raise(window)
        }
    }

    private func record(pid: pid_t, bundleID: String?) {
        let isFinder = bundleID == FocusReturnPolicy.finderBundleID
        if isFinder, let until = ignoreFinderUntil, ContinuousClock.now < until { return }
        let focused = isFinder ? ax.focusedWindow(ofApp: pid) : nil
        let event = ActivationEvent(pid: pid, bundleID: bundleID,
                                    visorIsFinderKeyWindow: focused.map(isVisorWindow) ?? false)
        guard let newTarget = policy.returnTarget(for: event) else { return }
        target = newTarget
        finderWindow = focused
    }
}
