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
