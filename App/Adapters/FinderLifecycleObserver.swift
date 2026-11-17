import AppKit
import VisorCore

/// Reports Finder launches and terminations (Finder relaunch invalidates every AE id and AX element).
@MainActor
final class FinderLifecycleObserver {
    var onLaunch: ((pid_t) -> Void)?
    var onTerminate: (() -> Void)?
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                         queue: .main) { [weak self] note in
            guard let pid = Self.finderPID(note) else { return }
            MainActor.assumeIsolated { self?.onLaunch?(pid) }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                         queue: .main) { [weak self] note in
            guard Self.finderPID(note) != nil else { return }
            MainActor.assumeIsolated { self?.onTerminate?() }
        })
    }

    private nonisolated static func finderPID(_ note: Notification) -> pid_t? {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == FocusReturnPolicy.finderBundleID else { return nil }
        return app.processIdentifier
    }
}
