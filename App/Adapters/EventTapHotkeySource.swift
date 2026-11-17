// EventTapHotkeySource — system-wide hotkeys via a single active CGEventTap (plan D4).
//
// Public API (main actor):
//   struct HotkeyConfig { doubleTapModifier: ModifierKey?; combo: KeyCombo?; isSuspended: Bool }
//   enum HotkeyTrigger { case doubleTap, combo }
//   final class EventTapHotkeySource {
//       init(onTrigger: @escaping @MainActor @Sendable (HotkeyTrigger) -> Void)
//       var config: HotkeyConfig { get }                       // current shared config
//       func setBindings(doubleTapModifier: ModifierKey?, combo: KeyCombo?)  // synchronous, live (AC-H5)
//       var isSuspended: Bool { get set }                      // true while the combo recorder is recording
//       var isActive: Bool { get }                             // tap exists and is enabled
//       @discardableResult func start() -> Bool                // false when the tap could not be created (no Accessibility)
//       func stop()
//   }
// `start()` may be called again at any time (e.g. right after Accessibility is granted); while started, a 5 s health
// check recreates the tap if it was disabled or could not be created earlier, so no relaunch is needed.
//
// Threading: the tap and its run-loop source live on a dedicated thread ("FinderVisor.EventTap") with its own
// CFRunLoop. Detector/matcher state is touched only on that thread. Config crosses threads through an
// OSAllocatedUnfairLock. Triggers are delivered to the main actor; nothing else (no AX/AE/AppKit) runs on the tap thread.

import ApplicationServices
import CoreGraphics
import Foundation
import os
import VisorCore

/// Hotkey configuration shared with the tap thread.
struct HotkeyConfig: Equatable, Sendable {
    var doubleTapModifier: ModifierKey?
    var combo: KeyCombo?
    /// When true every event passes through untouched and nothing fires (combo recording in progress).
    var isSuspended: Bool = false
}

/// What fired.
enum HotkeyTrigger: Sendable {
    case doubleTap
    case combo
}

@MainActor
final class EventTapHotkeySource {
    private let configLock = OSAllocatedUnfairLock(initialState: HotkeyConfig())
    private let onTrigger: @MainActor @Sendable (HotkeyTrigger) -> Void
    private var context: EventTapContext?
    private var thread: Thread?
    private var healthTimer: Timer?
    private var wantsRunning = false

    init(onTrigger: @escaping @MainActor @Sendable (HotkeyTrigger) -> Void) {
        self.onTrigger = onTrigger
    }

    var config: HotkeyConfig {
        configLock.withLock { $0 }
    }

    /// Writes the bindings into the shared lock; the next event on the tap thread uses them.
    func setBindings(doubleTapModifier: ModifierKey?, combo: KeyCombo?) {
        configLock.withLock {
            $0.doubleTapModifier = doubleTapModifier
            $0.combo = combo
        }
    }

    var isSuspended: Bool {
        get { configLock.withLock { $0.isSuspended } }
        set { configLock.withLock { $0.isSuspended = newValue } }
    }

    var isActive: Bool {
        guard let port = context?.port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    @discardableResult
    func start() -> Bool {
        wantsRunning = true
        startHealthTimer()
        if isActive { return true }
        tearDownTap()
        return createTap()
    }

    func stop() {
        wantsRunning = false
        healthTimer?.invalidate()
        healthTimer = nil
        tearDownTap()
    }

    // MARK: - Private

    private func createTap() -> Bool {
        let onTrigger = self.onTrigger
        let ctx = EventTapContext(config: configLock) { trigger in
            Task { @MainActor in onTrigger(trigger) }
        }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            runTapThread(ctx, ready: ready)
        }
        thread.name = "FinderVisor.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard ctx.port != nil else {
            // Thread already exited (tapCreate returned nil).
            return false
        }
        self.context = ctx
        self.thread = thread
        return true
    }

    private func tearDownTap() {
        guard let ctx = context else { return }
        // Non-blocking: the old tap passes every event through as soon as stop is requested and finishes tearing
        // itself down on its own thread, so a following start() cannot double-handle events.
        ctx.requestStop()
        context = nil
        thread = nil
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthCheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func healthCheck() {
        guard wantsRunning, !isActive, AXIsProcessTrusted() else { return }
        tearDownTap()
        _ = createTap()
    }
}

// MARK: - Tap thread

/// State shared between the main actor and the tap thread. Fields marked "tap thread only" are never touched elsewhere.
private final class EventTapContext: @unchecked Sendable {
    let config: OSAllocatedUnfairLock<HotkeyConfig>
    let deliver: @Sendable (HotkeyTrigger) -> Void

    // Tap thread only.
    var detector = DoubleTapDetector(modifier: nil)
    var matcher = ComboMatcher(combo: nil)
    var applied: HotkeyConfig?
    var wasSuspended = false

    // Cross-thread, guarded by `lock`.
    private let lock = NSLock()
    private var _port: CFMachPort?
    private var _runLoop: CFRunLoop?
    private var _stopRequested = false

    init(config: OSAllocatedUnfairLock<HotkeyConfig>, deliver: @escaping @Sendable (HotkeyTrigger) -> Void) {
        self.config = config
        self.deliver = deliver
    }

    var port: CFMachPort? {
        lock.lock(); defer { lock.unlock() }
        return _port
    }

    var stopRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return _stopRequested
    }

    func installed(port: CFMachPort?, runLoop: CFRunLoop?) {
        lock.lock(); defer { lock.unlock() }
        _port = port
        _runLoop = runLoop
    }

    func requestStop() {
        lock.lock()
        _stopRequested = true
        let runLoop = _runLoop
        lock.unlock()
        if let runLoop { CFRunLoopStop(runLoop) }
    }
}

private func runTapThread(_ ctx: EventTapContext, ready: DispatchSemaphore) {
    let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
    guard let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: eventTapCallback,
        userInfo: Unmanaged.passUnretained(ctx).toOpaque()
    ) else {
        ready.signal()
        return
    }
    let runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    ctx.installed(port: port, runLoop: runLoop)
    ready.signal()

    // Bounded slices so a stop requested before the loop starts is still honoured.
    while !ctx.stopRequested {
        CFRunLoopRunInMode(.defaultMode, 1.0, false)
    }

    CGEvent.tapEnable(tap: port, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    CFMachPortInvalidate(port)
    ctx.installed(port: nil, runLoop: nil)
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let ctx = Unmanaged<EventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
    if ctx.stopRequested { return Unmanaged.passUnretained(event) }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = ctx.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    let config = ctx.config.withLock { $0 }
    if config != ctx.applied {
        ctx.detector.modifier = config.doubleTapModifier
        ctx.matcher.combo = config.combo
        ctx.applied = config
    }
    guard let input = keyInput(type: type, event: event) else { return Unmanaged.passUnretained(event) }

    if config.isSuspended {
        // Keep the detector's modifier state current (result ignored) so resuming mid-press cannot misfire.
        if case .flagsChanged = input { _ = ctx.detector.process(input) }
        ctx.wasSuspended = true
        return Unmanaged.passUnretained(event)
    }
    if ctx.wasSuspended {
        ctx.wasSuspended = false
        ctx.detector.reset()
    }

    let tapped = ctx.detector.process(input)
    let comboResult = ctx.matcher.process(input)
    if tapped { ctx.deliver(.doubleTap) }
    switch comboResult {
    case .passThrough:
        return Unmanaged.passUnretained(event)
    case .fire:
        ctx.deliver(.combo)
        return nil
    case .swallow:
        return nil
    }
}

private func keyInput(type: CGEventType, event: CGEvent) -> KeyInput? {
    let modifiers = modifierSet(event.flags)
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    // Seconds on a monotonic clock; CGEvent.timestamp units differ across architectures.
    let now = ProcessInfo.processInfo.systemUptime
    switch type {
    case .flagsChanged:
        return .flagsChanged(modifiers: modifiers, keyCode: keyCode, timestamp: now)
    case .keyDown:
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        return .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, timestamp: now)
    case .keyUp:
        return .keyUp(keyCode: keyCode, modifiers: modifiers, timestamp: now)
    default:
        return nil
    }
}

private func modifierSet(_ flags: CGEventFlags) -> ModifierSet {
    var set: ModifierSet = []
    if flags.contains(.maskCommand) { set.insert(.command) }
    if flags.contains(.maskControl) { set.insert(.control) }
    if flags.contains(.maskAlternate) { set.insert(.option) }
    if flags.contains(.maskShift) { set.insert(.shift) }
    if flags.contains(.maskSecondaryFn) { set.insert(.function) }
    return set
}
