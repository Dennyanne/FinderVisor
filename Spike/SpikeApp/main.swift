// FinderVisorSpike.app — LSUIElement spike app for TCC-attributed checks (plan Step 1):
//   S3(c) an active event tap created after the Accessibility grant works without relaunch;
//   S3(d) whether Input Monitoring is needed in addition to Accessibility for an active tap;
//   S4    focus return from a background LSUIElement app: AXFrontmost vs activate() vs yieldActivation,
//         and re-raising the previously focused Finder window when the return target is Finder.
// Launch with `open build/FinderVisorSpike.app` (never from a terminal binary path, or TCC attributes to the terminal).
// Results go to the window and to ~/Library/Logs/FinderVisorSpike.log. Key contents are never logged, only counts.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FinderVisorSpike.log")

func nowMs() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000 }

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    guard let v = axCopy(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func focusedAppPid() -> pid_t? {
    guard let app = axElement(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else { return nil }
    var pid: pid_t = 0
    return AXUIElementGetPid(app, &pid) == .success ? pid : nil
}

func aeFinderStatus(ask: Bool) -> String {
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
    guard let desc = target.aeDesc else { return "error" }
    let st = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    switch st {
    case noErr: return "granted"
    case OSStatus(errAEEventNotPermitted): return "denied"
    case OSStatus(errAEEventWouldRequireUserConsent): return "notDetermined"
    case OSStatus(procNotFound): return "finderNotRunning"
    default: return "error(\(st))"
    }
}

// MARK: - Event tap (dedicated thread + CFRunLoop, plan D4)

final class TapBox: @unchecked Sendable {
    let lock = NSLock()
    var tap: CFMachPort?
    var runLoop: CFRunLoop?
    var keyDownsSeen = 0
    var swallowed = 0
    var swallowingKeyCode: Int64 = -1
    var reenabled = 0
}

func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<TapBox>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        box.lock.lock(); let t = box.tap; box.reenabled += 1; box.lock.unlock()
        if let t { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let mods = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    box.lock.lock(); defer { box.lock.unlock() }
    if type == .keyDown {
        box.keyDownsSeen += 1
        if keyCode == Int64(kVK_ANSI_F) && mods == .maskAlternate {
            box.swallowingKeyCode = keyCode
            box.swallowed += 1
            return nil
        }
        if keyCode == box.swallowingKeyCode { return nil }   // autorepeat
    } else if keyCode == box.swallowingKeyCode {
        box.swallowingKeyCode = -1
        return nil
    }
    return Unmanaged.passUnretained(event)
}

/// Starts the tap thread; returns whether CGEvent.tapCreate succeeded.
func startTapThread(_ box: TapBox) -> Bool {
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(box).toOpaque()) else {
            ready.signal()
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        box.lock.lock(); box.tap = tap; box.runLoop = CFRunLoopGetCurrent(); box.lock.unlock()
        ready.signal()
        CFRunLoopRun()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        CFMachPortInvalidate(tap)
        box.lock.lock(); box.tap = nil; box.runLoop = nil; box.lock.unlock()
    }
    thread.name = "FinderVisor.EventTap"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    box.lock.lock(); defer { box.lock.unlock() }
    return box.tap != nil
}

func stopTapThread(_ box: TapBox) {
    box.lock.lock(); let rl = box.runLoop; box.lock.unlock()
    if let rl { CFRunLoopStop(rl) }
}

// MARK: - App

@MainActor final class SpikeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: NSTextView!
    var tapBox: TapBox?
    var tapTimer: Timer?
    var tapAttemptStart = 0.0
    var tapAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        log("FinderVisorSpike launched: bundle=\(Bundle.main.bundleIdentifier ?? "?") path=\(Bundle.main.bundlePath) pid=\(getpid())")
        logStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let b = tapBox { stopTapThread(b) }
    }

    func log(_ s: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
        textView.textStorage?.append(NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.textColor]))
        textView.scrollToEndOfDocument(nil)
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FinderVisorSpike"
        window.isReleasedWhenClosed = false
        let buttons: [(String, Selector)] = [
            ("Status", #selector(logStatus)),
            ("Prompt Accessibility", #selector(promptAX)),
            ("Request Input Monitoring", #selector(requestListen)),
            ("Request Automation (Finder)", #selector(requestAE)),
            ("S3(c/d) Start tap (retry 1 s)", #selector(startTapLoop)),
            ("Stop tap", #selector(stopTap)),
            ("S4 focus return (in 3 s)", #selector(runS4)),
            ("S4 Finder window re-raise (in 3 s)", #selector(runS4Finder)),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        let row1 = NSStackView(), row2 = NSStackView()
        for (i, b) in buttons.enumerated() {
            let btn = NSButton(title: b.0, target: self, action: b.1)
            (i < 4 ? row1 : row2).addArrangedSubview(btn)
        }
        let scroll = NSTextView.scrollableTextView()
        textView = (scroll.documentView as! NSTextView)
        textView.isEditable = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 720).isActive = true
        stack.addArrangedSubview(row1)
        stack.addArrangedSubview(row2)
        stack.addArrangedSubview(scroll)
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func logStatus() {
        log("STATUS axTrusted=\(AXIsProcessTrusted()) listenEvent(InputMonitoring)=\(CGPreflightListenEventAccess()) "
            + "postEvent=\(CGPreflightPostEventAccess()) automationFinder=\(aeFinderStatus(ask: false)) "
            + "tapRunning=\(tapBox != nil)")
    }

    @objc func promptAX() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        log("AXIsProcessTrustedWithOptions(prompt) -> \(AXIsProcessTrustedWithOptions(opts))")
    }

    @objc func requestListen() {
        log("CGRequestListenEventAccess -> \(CGRequestListenEventAccess())")
    }

    @objc func requestAE() {
        log("requesting Automation→Finder (may show a consent dialog)…")
        Task.detached {
            let r = aeFinderStatus(ask: true)
            await MainActor.run { (NSApp.delegate as? SpikeDelegate)?.log("Automation→Finder -> \(r)") }
        }
    }

    /// S3(c): tries to create the active tap every second without relaunching. Grant Accessibility while
    /// it is retrying; the log records the attempt at which creation first succeeds.
    /// S3(d): status line records whether Input Monitoring was granted when the tap worked.
    @objc func startTapLoop() {
        guard tapBox == nil, tapTimer == nil else { log("tap already running/retrying"); return }
        tapAttemptStart = nowMs()
        tapAttempts = 0
        log("S3(c): attempting tap creation every 1 s for up to 180 s (grant Accessibility now if not yet granted)")
        tapTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? SpikeDelegate)?.tapAttempt() }
        }
        tapAttempt()
    }

    func tapAttempt() {
        tapAttempts += 1
        let box = TapBox()
        if startTapThread(box) {
            tapTimer?.invalidate(); tapTimer = nil
            tapBox = box
            log(String(format: "S3(c) RESULT tapCreated=true attempt=%d afterMs=%.0f axTrusted=%@ inputMonitoring=%@ (no relaunch)",
                       tapAttempts, nowMs() - tapAttemptStart, "\(AXIsProcessTrusted())", "\(CGPreflightListenEventAccess())"))
            log("S3(d): now press Option+F in TextEdit a few times, then press 'Stop tap' and check counts + whether 'ƒ' appeared.")
        } else if tapAttempts == 1 || tapAttempts % 10 == 0 {
            log("tap attempt \(tapAttempts): tapCreate=nil axTrusted=\(AXIsProcessTrusted()) inputMonitoring=\(CGPreflightListenEventAccess())")
        }
        if tapAttempts >= 180 { tapTimer?.invalidate(); tapTimer = nil; log("S3(c) RESULT tapCreated=false after 180 attempts") }
    }

    @objc func stopTap() {
        tapTimer?.invalidate(); tapTimer = nil
        guard let b = tapBox else { log("no tap running"); return }
        b.lock.lock()
        let seen = b.keyDownsSeen, sw = b.swallowed, re = b.reenabled
        b.lock.unlock()
        stopTapThread(b)
        tapBox = nil
        log("S3(d) RESULT keyDownsSeenFromOtherApps=\(seen) swallowedOptionF=\(sw) reenabled=\(re) "
            + "inputMonitoring=\(CGPreflightListenEventAccess()) axTrusted=\(AXIsProcessTrusted()) — tap removed")
    }

    // MARK: S4

    func waitFrontmost(_ pid: pid_t, timeoutMs: Double) -> Double? {
        let t0 = nowMs()
        while nowMs() - t0 < timeoutMs {
            if focusedAppPid() == pid { return nowMs() - t0 }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
        return nil
    }

    func finderApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    }

    /// Simulates "Visor shown → hidden": Finder frontmost, then return focus to the app that was frontmost
    /// 3 s after the click (switch to e.g. TextEdit during the countdown) using each method.
    @objc func runS4() {
        log("S4: switch to the return-target app (e.g. TextEdit) within 3 s…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            guard let targetPid = focusedAppPid(), let target = NSRunningApplication(processIdentifier: targetPid),
                  let finder = finderApp() else { log("S4: no frontmost app / Finder"); return }
            guard targetPid != getpid(), targetPid != finder.processIdentifier else {
                log("S4: frontmost is this spike or Finder; pick another app"); return
            }
            log("S4: return target = \(target.bundleIdentifier ?? "?") pid=\(targetPid)")
            for method in ["axFrontmost", "activate", "yieldActivation"] {
                AXUIElementSetAttributeValue(AXUIElementCreateApplication(finder.processIdentifier),
                                             kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                let finderUp = waitFrontmost(finder.processIdentifier, timeoutMs: 1000)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                let t0 = nowMs()
                switch method {
                case "axFrontmost":
                    AXUIElementSetAttributeValue(AXUIElementCreateApplication(targetPid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                case "activate":
                    target.activate(options: [])
                default:
                    NSApp.yieldActivation(to: target)
                    target.activate(from: NSRunningApplication.current, options: [])
                }
                let ms = waitFrontmost(targetPid, timeoutMs: 1500)
                log("S4 RESULT method=\(method) finderWasFrontmost=\(finderUp != nil) returned=\(ms != nil) "
                    + "ms=\(ms.map { String(format: "%.1f", $0) } ?? "timeout") pass150=\((ms ?? .infinity) <= 150) total=\(String(format: "%.0f", nowMs() - t0))")
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            }
        }
    }

    /// Return target is Finder: record its focused window W, move focus away (to this spike), then return by
    /// raising W (AXRaise + AXMain) and making Finder frontmost; pass if Finder's focused window is W.
    @objc func runS4Finder() {
        log("S4-Finder: click a Finder window (not the Visor) within 3 s…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            guard let finder = finderApp(), focusedAppPid() == finder.processIdentifier else {
                log("S4-Finder: Finder was not frontmost"); return
            }
            let fApp = AXUIElementCreateApplication(finder.processIdentifier)
            guard let w = axElement(fApp, kAXFocusedWindowAttribute) else { log("S4-Finder: no focused Finder window"); return }
            NSApp.activate()
            _ = waitFrontmost(getpid(), timeoutMs: 1000)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            let t0 = nowMs()
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(fApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            var ok = false
            while nowMs() - t0 < 1500 {
                if focusedAppPid() == finder.processIdentifier, let fw = axElement(fApp, kAXFocusedWindowAttribute), CFEqual(fw, w) {
                    ok = true; break
                }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
            }
            log("S4-Finder RESULT reRaisedPreviousWindow=\(ok) ms=\(String(format: "%.1f", nowMs() - t0))")
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { SpikeDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
