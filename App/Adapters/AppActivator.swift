import AppKit

/// Activates other applications from a background (LSUIElement) app.
@MainActor
protocol AppActivator {
    var finderPID: pid_t? { get }
    var isFinderHidden: Bool { get }
    var frontmostApplication: (pid: pid_t, bundleID: String?)? { get }
    func hideFinder()
    func unhideFinder()
    /// Brings `pid` to the front: AX `AXFrontmost` first, `NSRunningApplication.activate` as fallback.
    /// Returns false if the app is no longer running.
    @discardableResult func activate(pid: pid_t) -> Bool
}

final class LiveAppActivator: AppActivator {
    nonisolated static let finderBundleID = "com.apple.finder"
    private let ax: AXWindowService

    init(ax: AXWindowService) {
        self.ax = ax
    }

    private var finder: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.finderBundleID).first { !$0.isTerminated }
    }

    var finderPID: pid_t? { finder?.processIdentifier }
    var isFinderHidden: Bool { finder?.isHidden ?? false }

    var frontmostApplication: (pid: pid_t, bundleID: String?)? {
        NSWorkspace.shared.frontmostApplication.map { ($0.processIdentifier, $0.bundleIdentifier) }
    }

    func hideFinder() {
        finder?.hide()
    }

    func unhideFinder() {
        finder?.unhide()
    }

    @discardableResult func activate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        if ax.setFrontmost(pid: pid) { return true }
        NSApp.yieldActivation(to: app)
        return app.activate()
    }
}
