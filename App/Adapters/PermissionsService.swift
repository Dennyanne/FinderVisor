// PermissionsService — TCC status, requests, deep links and stale-grant detection (plan Step 5, AC-S5).
//
// Public API (main actor, @Observable):
//   enum AutomationPermission { case granted, denied, notDetermined, finderNotRunning, unknown(Int32) }
//   enum PermissionPane { case accessibility, automation, inputMonitoring }
//   init(defaults: UserDefaults = .standard)
//   private(set) var accessibilityGranted: Bool
//   private(set) var automation: AutomationPermission
//   private(set) var inputMonitoringGranted: Bool        // informational only, never required
//   private(set) var staleGrantSuspected: Bool           // was granted once, now reports false (rebuild / cdhash change)
//   var allRequiredGranted: Bool { get }                 // accessibility && automation == .granted
//   var onAccessibilityGranted: (@MainActor () -> Void)? // fired on a false → true transition (start the tap here)
//   func refresh() async                                 // AX on main, Apple Events check off main
//   func requestAccessibility()                          // system prompt + opens the Accessibility pane
//   func requestAutomation() async                       // AEDeterminePermission… askUserIfNeeded: true, off main
//   func openSettings(_ pane: PermissionPane)
//   func startPolling() / func stopPolling()             // 1 s polling while the permissions view is open
// Input Monitoring is shown for information only (Spike S3(d) did not establish that the active tap needs it).

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

enum AutomationPermission: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    case finderNotRunning
    case unknown(Int32)
}

enum PermissionPane: Sendable {
    case accessibility
    case automation
    case inputMonitoring

    var url: URL {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .automation: "Privacy_Automation"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        // Force-unwrap is safe: constant, well-formed URL.
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

@MainActor
@Observable
final class PermissionsService {
    static let hadAccessibilityGrantKey = "hadAccessibilityGrant"

    private(set) var accessibilityGranted: Bool
    private(set) var automation: AutomationPermission = .notDetermined
    private(set) var inputMonitoringGranted: Bool
    private(set) var staleGrantSuspected = false

    @ObservationIgnored var onAccessibilityGranted: (@MainActor () -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pollTimer: Timer?
    /// The refresh currently running; concurrent callers await it instead of returning stale values.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var allRequiredGranted: Bool {
        accessibilityGranted && automation == .granted
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        updateStaleGrantFlag()
    }

    /// Re-reads every permission. If a refresh is already running, waits for it, so callers always see the result of
    /// a completed refresh (e.g. a hotkey during launch never sees the initial `.notDetermined`).
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        let wasGranted = accessibilityGranted
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        updateStaleGrantFlag()
        automation = await Self.determineAutomation(askUserIfNeeded: false)
        if !wasGranted, accessibilityGranted {
            onAccessibilityGranted?()
        }
    }

    func requestAccessibility() {
        // String literal instead of kAXTrustedCheckOptionPrompt (a mutable C global, not concurrency-safe).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings(.accessibility)
    }

    func requestAutomation() async {
        automation = await Self.determineAutomation(askUserIfNeeded: true)
        if automation == .denied {
            openSettings(.automation)
        }
    }

    func openSettings(_ pane: PermissionPane) {
        NSWorkspace.shared.open(pane.url)
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Task { await refresh() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Private

    private func updateStaleGrantFlag() {
        if accessibilityGranted {
            defaults.set(true, forKey: Self.hadAccessibilityGrantKey)
            staleGrantSuspected = false
        } else {
            staleGrantSuspected = defaults.bool(forKey: Self.hadAccessibilityGrantKey)
        }
    }

    /// Runs `AEDeterminePermissionToAutomateTarget` for Finder off the main thread (it can block on the prompt).
    private nonisolated static func determineAutomation(askUserIfNeeded: Bool) async -> AutomationPermission {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            guard let desc = target.aeDesc else { return AutomationPermission.unknown(Int32(paramErr)) }
            let status = AEDeterminePermissionToAutomateTarget(
                desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded
            )
            switch Int(status) {
            case Int(noErr): return .granted
            case Int(errAEEventNotPermitted): return .denied
            case Int(errAEEventWouldRequireUserConsent): return .notDetermined
            case Int(procNotFound): return .finderNotRunning
            default: return .unknown(Int32(status))
            }
        }.value
    }
}
