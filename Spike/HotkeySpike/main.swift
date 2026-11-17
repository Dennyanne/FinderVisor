// HotkeySpike — Phase 0 hotkey spike for FinderVisor (plan D4, check S3 a/b).
//
//   HotkeySpike carbon [--listen N]   S3(a): RegisterEventHotKey Option+F (and Cmd+Option+F as control);
//                                     optionally pump the event loop N s (≤10) and count presses.
//   HotkeySpike tap [--seconds N]     S3(b): active CGEventTap (dedicated thread + CFRunLoop) that swallows
//                                     Option+F for N s (default 8, max 10). Press Option+F in TextEdit
//                                     meanwhile: no "ƒ" must appear. The tap is disabled, removed and
//                                     invalidated before exit (also on Ctrl-C).
//   HotkeySpike all [--seconds N]     carbon then tap.
// Results attributed to the terminal's TCC grants; S3(c)/(d) belong in FinderVisorSpike.app.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

func emit(_ check: String, _ fields: [(String, String)]) {
    print("RESULT check=\(check) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
    fflush(stdout)
}

func info(_ s: String) { print("# " + s); fflush(stdout) }

@MainActor func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

// MARK: - S3(a) Carbon

nonisolated(unsafe) var carbonPresses: [UInt32: Int] = [:]

@MainActor func runCarbon(listenSeconds: Double) {
    _ = NSApplication.shared
    NSApplication.shared.setActivationPolicy(.prohibited)
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let handlerStatus = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
        var hk = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &hk)
        carbonPresses[hk.id, default: 0] += 1
        return noErr
    }, 1, &spec, nil, nil)

    let combos: [(id: UInt32, name: String, mods: Int)] = [
        (1, "Option+F", optionKey),
        (2, "Option+Shift+F", optionKey | shiftKey),
        (3, "Cmd+Option+F(control)", cmdKey | optionKey),
    ]
    var refs: [EventHotKeyRef] = []
    for c in combos {
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(c.mods), EventHotKeyID(signature: OSType(0x4656_484B), id: c.id),
                                     GetEventDispatcherTarget(), 0, &ref)
        if let ref { refs.append(ref) }
        emit("S3a-register", [("combo", "\"\(c.name)\""), ("status", "\(st)"), ("registered", "\(st == noErr && ref != nil)")])
    }
    if listenSeconds > 0 {
        let secs = min(listenSeconds, 10)
        info("Press Option+F, then Cmd+Option+F within \(Int(secs)) s (in any app)...")
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
            NSApplication.shared.stop(nil)
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApplication.shared.postEvent(e, atStart: true)
            }
        }
        NSApplication.shared.run()
        for c in combos {
            emit("S3a-fired", [("combo", "\"\(c.name)\""), ("presses", "\(carbonPresses[c.id] ?? 0)")])
        }
    }
    for r in refs { UnregisterEventHotKey(r) }
    emit("S3a", [("handlerStatus", "\(handlerStatus)"),
                 ("note", "\"registration success does not imply delivery; macOS 15+ rejects Option-only combos at register or delivery\"")])
}

// MARK: - S3(b) active event tap

final class TapBox: @unchecked Sendable {
    let lock = NSLock()
    var tap: CFMachPort?
    var runLoop: CFRunLoop?
    var swallowedDown = 0
    var swallowedUp = 0
    var keyDownsSeen = 0
    var reenabled = 0
    var swallowingKeyCode: Int64 = -1
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
            box.swallowedDown += 1
            return nil
        }
        if keyCode == box.swallowingKeyCode && event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
    } else if keyCode == box.swallowingKeyCode {
        box.swallowingKeyCode = -1
        box.swallowedUp += 1
        return nil
    }
    return Unmanaged.passUnretained(event)
}

nonisolated(unsafe) var activeTapBox: TapBox?

func stopTap(_ box: TapBox) {
    box.lock.lock(); let rl = box.runLoop; box.lock.unlock()
    if let rl { CFRunLoopStop(rl) }
}

@MainActor func runTap(seconds: Double) {
    let secs = min(max(seconds, 1), 10)
    let box = TapBox()
    activeTapBox = box
    let ready = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let created = UnsafeSendableFlag()
    let thread = Thread {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: tapCallback,
                                    userInfo: Unmanaged.passUnretained(box).toOpaque())
        var source: CFRunLoopSource?
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            box.lock.lock(); box.tap = tap; box.runLoop = CFRunLoopGetCurrent(); box.lock.unlock()
            created.value = true
        }
        ready.signal()
        if let tap {
            CFRunLoopRun()
            // Teardown on the tap thread: disable, remove source, invalidate.
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFMachPortInvalidate(tap)
            box.lock.lock(); box.tap = nil; box.runLoop = nil; box.lock.unlock()
        }
        finished.signal()
    }
    thread.name = "FinderVisor.EventTap"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    emit("S3b-create", [("tapCreated", "\(created.value)"), ("axTrusted", "\(AXIsProcessTrusted())"),
                        ("listenEventAccess", "\(CGPreflightListenEventAccess())"), ("postEventAccess", "\(CGPreflightPostEventAccess())")])
    guard created.value else {
        info("CGEvent.tapCreate returned nil: the host process lacks Accessibility (and/or Input Monitoring). No tap installed.")
        finished.wait()
        return
    }
    info("Active tap installed for \(Int(secs)) s. Switch to TextEdit and press Option+F: no 'ƒ' should appear.")
    let deadline = Date(timeIntervalSinceNow: secs)
    while Date() < deadline { RunLoop.current.run(mode: .default, before: min(deadline, Date(timeIntervalSinceNow: 0.1))) }
    stopTap(box)
    finished.wait()
    box.lock.lock()
    let removed = box.tap == nil
    emit("S3b", [("seconds", "\(Int(secs))"), ("keyDownsSeen", "\(box.keyDownsSeen)"), ("swallowedOptionFDown", "\(box.swallowedDown)"),
                 ("swallowedOptionFUp", "\(box.swallowedUp)"), ("reenabled", "\(box.reenabled)"), ("tapRemoved", "\(removed)"),
                 ("pass", box.swallowedDown > 0 ? "true(user-confirms-no-ƒ)" : "untested(no-Option+F-pressed)")])
    box.lock.unlock()
    activeTapBox = nil
}

final class UnsafeSendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}

// MARK: - main

@MainActor func mainEntry() -> Int32 {
    signal(SIGINT, SIG_IGN)
    let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigSrc.setEventHandler {
        if let b = activeTapBox { stopTap(b); usleep(100_000) }
        info("interrupted; tap stopped")
        exit(130)
    }
    sigSrc.resume()
    let cmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "help"
    let seconds = Double(arg("--seconds") ?? "8") ?? 8
    switch cmd {
    case "carbon": runCarbon(listenSeconds: Double(arg("--listen") ?? "0") ?? 0)
    case "tap": runTap(seconds: seconds)
    case "all":
        runCarbon(listenSeconds: Double(arg("--listen") ?? "0") ?? 0)
        runTap(seconds: seconds)
    default:
        print("usage: HotkeySpike carbon [--listen N] | tap [--seconds N≤10] | all")
        return cmd == "help" ? 0 : 2
    }
    _ = sigSrc
    return 0
}

exit(MainActor.assumeIsolated { mainEntry() })
