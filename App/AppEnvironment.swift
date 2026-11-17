import AppKit
import SwiftUI
import VisorCore

/// Composition root: builds the adapters and controllers and connects hotkeys, permissions, settings and the Visor.
@MainActor
final class AppEnvironment {
    let hotkeys: EventTapHotkeySource
    let settings: SettingsStore
    let loginItem: LoginItemService
    let permissions: PermissionsService
    let visor: VisorController

    private let locator: VisorWindowLocator
    private let focus: FocusReturnTracker
    private let finderLifecycle = FinderLifecycleObserver()
    private var settingsWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    init() {
        let relay = TriggerRelay()
        hotkeys = EventTapHotkeySource { _ in relay.fire() }
        settings = SettingsStore(hotkeys: hotkeys)
        loginItem = LoginItemService()
        permissions = PermissionsService()

        let ax = LiveAXWindowService()
        let activator = LiveAppActivator(ax: ax)
        let windowList = LiveWindowListProvider()
        let locator = VisorWindowLocator(scripting: LiveFinderScripting(), ax: ax, windowList: windowList,
                                         activator: activator)
        let focus = FocusReturnTracker(ax: ax, activator: activator) { [weak locator] window in
            locator?.isVisor(window) ?? false
        }
        let settings = settings
        visor = VisorController(locator: locator, ax: ax, windowList: windowList, screens: LiveScreenProvider(),
                                activator: activator, hider: MinimizeHider(ax: ax), focus: focus,
                                heightPercent: { settings.heightPercent })
        self.locator = locator
        self.focus = focus
        relay.action = { [weak self] in self?.toggleVisor() }
    }

    func start() {
        focus.start()
        finderLifecycle.onLaunch = { [weak self] pid in self?.locator.finderLaunched(pid: pid) }
        finderLifecycle.onTerminate = { [weak self] in self?.locator.finderTerminated() }
        finderLifecycle.start()
        visor.onError = { [weak self] error in
            if (error as? FinderScriptingError) == .notAuthorized { self?.showPermissions() }
        }
        permissions.onAccessibilityGranted = { [weak self] in self?.hotkeys.start() }
        hotkeys.start()
        Task {
            await permissions.refresh()
            if permissions.allRequiredGranted {
                // Re-attach to a Visor left over from a previous FinderVisor run.
                _ = await locator.resolve()
            } else {
                showPermissions()
            }
        }
    }

    /// Hotkey and menu entry point. Missing permissions → permissions window instead of a toggle (plan Step 5).
    func toggleVisor() {
        Task {
            await permissions.refresh()
            guard permissions.allRequiredGranted else {
                showPermissions()
                return
            }
            if !hotkeys.isActive { hotkeys.start() }
            await visor.toggle()
        }
    }

    func showSettings() {
        settingsWindow = present(settingsWindow, title: "FinderVisor Settings") {
            SettingsView(settings: settings, loginItem: loginItem)
        }
    }

    func showPermissions() {
        permissionsWindow = present(permissionsWindow, title: "FinderVisor Permissions") {
            PermissionsView(permissions: permissions)
        }
    }

    private func present<Content: View>(_ existing: NSWindow?, title: String,
                                        content: () -> Content) -> NSWindow {
        let window = existing ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

/// Lets the hotkey source (created first) call back into the environment once it exists.
@MainActor
private final class TriggerRelay {
    var action: (() -> Void)?

    func fire() {
        action?()
    }
}
