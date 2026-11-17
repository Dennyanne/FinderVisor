// HideSpike — Phase 0 hide-strategy spike for FinderVisor (plan D2/D3, Step 1).
//
// Run from Terminal (Terminal needs Accessibility + Automation→Finder):
//   HideSpike perm                         permission status + responsible process chain
//   HideSpike config                       detected display / Dock / Stage Manager configuration
//   HideSpike s2                           identity: AE id vs kCGWindowNumber, optionOnScreenAboveWindow
//   HideSpike probe                        P1 park candidates: requested vs actual position, sliver area
//   HideSpike run [--strategy p1|p2|p3|all] [--cycles 20] [--park br|bl|b|r|l] [--height 40]
//                                          automated H-1, H-2 (geometry), H-3, H-4, H-6 + show/hide latency
//   HideSpike h9  [--strategy p1] [--duration 120]   re-park on screen-parameter change (user changes displays)
//   HideSpike h10 [--strategy p1]                    guided Finder relaunch while hidden (user runs killall Finder)
//   HideSpike manual --check H-2|H-5|H-7|H-8 [--strategy p1]   guided manual checks
//
// Output: machine-readable "RESULT check=... key=value" lines and a "SUMMARY" block.
// Safety: only windows created by this process are moved/minimized/closed. P2 app-hide of Finder is
// always undone (unhide) on exit. This tool never terminates Finder.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let finderBundleID = "com.apple.finder"

struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - Output

var resultLines: [String] = []

@MainActor func emit(_ check: String, _ fields: [(String, String)]) {
    let line = "RESULT check=\(check) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    print(line)
    resultLines.append(line)
    fflush(stdout)
}

func info(_ s: String) {
    print("# " + s)
    fflush(stdout)
}

func f1(_ x: Double) -> String { String(format: "%.1f", x) }
func rectStr(_ r: CGRect?) -> String {
    guard let r else { return "nil" }
    return "\(Int(r.minX.rounded())),\(Int(r.minY.rounded())),\(Int(r.width.rounded()))x\(Int(r.height.rounded()))"
}

func nowMs() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000 }

func median(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func approxEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 2) -> Bool {
    abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol
        && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
}

func maxDeviation(_ a: CGRect, _ b: CGRect) -> Double {
    Double(max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)))
}

/// Sum of the area of `r` that lies on any display (displays do not overlap).
func intersectionArea(_ r: CGRect, _ displays: [CGRect]) -> Double {
    displays.reduce(0) { acc, d in
        let i = r.intersection(d)
        return acc + (i.isNull ? 0 : Double(i.width * i.height))
    }
}

/// Spin the run loop briefly so notifications / KVO (NSRunningApplication) get delivered.
@MainActor func pump(_ seconds: Double) {
    let end = Date(timeIntervalSinceNow: seconds)
    repeat {
        if !RunLoop.current.run(mode: .default, before: min(end, Date(timeIntervalSinceNow: 0.002))) {
            usleep(1000)
        }
    } while Date() < end
}

/// Poll `cond` until true or timeout; returns elapsed ms since `start`, or nil on timeout.
@MainActor func waitUntil(start: Double, timeoutMs: Double, _ cond: () -> Bool) -> Double? {
    while true {
        if cond() { return nowMs() - start }
        if nowMs() - start > timeoutMs { return nil }
        if !RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001)) { usleep(1000) }
    }
}

// MARK: - Shell / process helpers

func shell(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func processChain() -> [String] {
    var chain: [String] = []
    var pid = getpid()
    for _ in 0..<12 {
        let comm = shell("/bin/ps", ["-o", "comm=", "-p", "\(pid)"])
        let ppidStr = shell("/bin/ps", ["-o", "ppid=", "-p", "\(pid)"])
        chain.append("\(pid):\(comm)")
        guard let ppid = Int32(ppidStr), ppid > 1 else { break }
        pid = ppid
    }
    return chain
}

// MARK: - Permissions

enum AEPermission: String { case granted, denied, notDetermined, finderNotRunning, error }

func aePermissionForFinder(ask: Bool) -> (AEPermission, OSStatus) {
    let target = NSAppleEventDescriptor(bundleIdentifier: finderBundleID)
    guard let desc = target.aeDesc else { return (.error, -1) }
    let st = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    switch st {
    case noErr: return (.granted, st)
    case OSStatus(errAEEventNotPermitted): return (.denied, st)
    case OSStatus(errAEEventWouldRequireUserConsent): return (.notDetermined, st)
    case OSStatus(procNotFound): return (.finderNotRunning, st)
    default: return (.error, st)
    }
}

@MainActor func reportPermissions() -> (ax: Bool, ae: AEPermission) {
    let ax = AXIsProcessTrusted()
    let (ae, st) = aePermissionForFinder(ask: false)
    let chain = processChain()
    emit("perm", [("axTrusted", "\(ax)"), ("aeFinder", ae.rawValue), ("aeStatus", "\(st)"),
                  ("listenEvent", "\(CGPreflightListenEventAccess())")])
    info("process chain (self -> ancestors; TCC attributes to the responsible app at the top of the GUI chain):")
    for c in chain { info("  " + c) }
    return (ax, ae)
}

/// Exits with code 3 if Accessibility is missing or Automation is denied. A not-determined Automation
/// state is allowed: the first Apple Event will show the system consent prompt to the user.
@MainActor func requirePermissions() {
    let ax = AXIsProcessTrusted()
    let (ae, st) = aePermissionForFinder(ask: false)
    if !ax || ae == .denied || ae == .error {
        _ = reportPermissions()
        info("MISSING PERMISSION: accessibility=\(ax) automationFinder=\(ae.rawValue) (status \(st)).")
        info("Grant in System Settings > Privacy & Security > Accessibility / Automation for the host app above, then re-run.")
        exit(3)
    }
}

// MARK: - Configuration detection

func cgDisplays() -> [(id: CGDirectDisplayID, bounds: CGRect, main: Bool)] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    return ids.prefix(Int(n)).map { ($0, CGDisplayBounds($0), CGDisplayIsMain($0) != 0) }
}

/// Display frames in global top-left coordinates (same space as AX positions and CGWindow bounds).
func displayRects() -> [CGRect] { cgDisplays().map { $0.bounds } }

func detectConfig() -> (displays: String, dock: String, stageManager: String) {
    let ds = cgDisplays()
    var layout = "single"
    if ds.count >= 2, let main = ds.first(where: { $0.main }) {
        let others = ds.filter { !$0.main }
        let o = others[0].bounds
        let m = main.bounds
        if o.maxX <= m.minX { layout = "secondary-left" }
        else if o.maxY <= m.minY { layout = "secondary-above" }
        else if o.minX >= m.maxX { layout = "secondary-right" }
        else if o.minY >= m.maxY { layout = "secondary-below" }
        else { layout = "other" }
        if ds.count > 2 { layout += "+\(ds.count - 2)more" }
    }
    let orientation = shell("/usr/bin/defaults", ["read", "com.apple.dock", "orientation"])
    let autohide = shell("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"])
    let sm = shell("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GlobalEnabled"])
    let dock = (orientation.isEmpty ? "bottom" : orientation) + (autohide == "1" ? "(autohide)" : "")
    return (layout + " [" + ds.map { rectStr($0.bounds) + ($0.main ? "*" : "") }.joined(separator: " ") + "]",
            dock, sm == "1" ? "on" : "off")
}

@MainActor func reportConfig() {
    let c = detectConfig()
    emit("config", [("displays", "\"\(c.displays)\""), ("dock", c.dock), ("stageManager", c.stageManager)])
}

// MARK: - AX helpers

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    return v
}

func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    guard let v = axCopy(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func axElements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    guard let arr = axCopy(el, attr) as? [AnyObject] else { return [] }
    return arr.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
}

func axString(_ el: AXUIElement, _ attr: String) -> String? { axCopy(el, attr) as? String }
func axBool(_ el: AXUIElement, _ attr: String) -> Bool? { (axCopy(el, attr) as? NSNumber)?.boolValue }
func axInt(_ el: AXUIElement, _ attr: String) -> Int? { (axCopy(el, attr) as? NSNumber)?.intValue }

func axPosition(_ el: AXUIElement) -> CGPoint? {
    guard let v = axCopy(el, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
}

func axSize(_ el: AXUIElement) -> CGSize? {
    guard let v = axCopy(el, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p = axPosition(el), let s = axSize(el) else { return nil }
    return CGRect(origin: p, size: s)
}

@discardableResult func axSetPosition(_ el: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
}

@discardableResult func axSetSize(_ el: AXUIElement, _ s: CGSize) -> AXError {
    var s = s
    guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
}

@discardableResult func axSetBool(_ el: AXUIElement, _ attr: String, _ b: Bool) -> AXError {
    AXUIElementSetAttributeValue(el, attr as CFString, (b ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
}

func focusedAppPid() -> pid_t? {
    guard let app = axElement(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) else { return nil }
    var pid: pid_t = 0
    return AXUIElementGetPid(app, &pid) == .success ? pid : nil
}

func activateViaAX(pid: pid_t) {
    axSetBool(AXUIElementCreateApplication(pid), kAXFrontmostAttribute, true)
}

// MARK: - CGWindowList helpers

struct CGWin {
    let number: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let onscreen: Bool
    let alpha: Double
}

func cgList(_ opt: CGWindowListOption, _ rel: CGWindowID = kCGNullWindowID) -> [CGWin] {
    guard let arr = CGWindowListCopyWindowInfo(opt, rel) as? [[String: Any]] else { return [] }
    return arr.compactMap { d in
        guard let n = d[kCGWindowNumber as String] as? Int,
              let pid = d[kCGWindowOwnerPID as String] as? Int,
              let bd = d[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: bd as CFDictionary) else { return nil }
        return CGWin(number: CGWindowID(n), pid: pid_t(pid), layer: d[kCGWindowLayer as String] as? Int ?? 0,
                     bounds: b, onscreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                     alpha: d[kCGWindowAlpha as String] as? Double ?? 1)
    }
}

func cgWindow(_ id: CGWindowID) -> CGWin? { cgList(.optionIncludingWindow, id).first }

/// Hidden per CGWindowList: not on screen, or on screen with zero area on every display.
func cgHidden(_ id: CGWindowID) -> Bool {
    guard let w = cgWindow(id), w.onscreen else { return true }
    return intersectionArea(w.bounds, displayRects()) == 0
}

func cgVisibleArea(_ id: CGWindowID) -> Double {
    guard let w = cgWindow(id), w.onscreen else { return 0 }
    return intersectionArea(w.bounds, displayRects())
}

// MARK: - Apple Events (Finder)

@MainActor @discardableResult func appleScript(_ src: String) throws -> NSAppleEventDescriptor {
    guard let script = NSAppleScript(source: src) else { throw SpikeError("bad script") }
    var err: NSDictionary?
    let r = script.executeAndReturnError(&err)
    if let err { throw SpikeError("AppleScript error: \(err[NSAppleScript.errorMessage] ?? err)") }
    return r
}

@MainActor @discardableResult func finderAS(_ body: String) throws -> NSAppleEventDescriptor {
    try appleScript("tell application \"Finder\"\n\(body)\nend tell")
}

func boundsLiteral(_ r: CGRect) -> String {
    "{\(Int(r.minX)), \(Int(r.minY)), \(Int(r.maxX)), \(Int(r.maxY))}"
}

@MainActor func aeCreateWindow(frame: CGRect) throws -> Int {
    let d = try finderAS("""
    set w to make new Finder window to home
    set bounds of w to \(boundsLiteral(frame))
    return id of w
    """)
    return Int(d.int32Value)
}

@MainActor func aeExists(_ id: Int) -> Bool {
    (try? finderAS("return exists Finder window id \(id)"))?.booleanValue ?? false
}

@MainActor func aeClose(_ id: Int) {
    _ = try? finderAS("if exists Finder window id \(id) then close Finder window id \(id)")
}

@MainActor func aeTarget(_ id: Int) -> String {
    (try? finderAS("return POSIX path of (target of Finder window id \(id) as alias)"))?.stringValue ?? "?"
}

@MainActor func aeSetTarget(_ id: Int, _ path: String) throws {
    try finderAS("set target of Finder window id \(id) to (POSIX file \"\(path)\" as alias)")
}

@MainActor func aeView(_ id: Int) -> String {
    guard let d = try? finderAS("return current view of Finder window id \(id)") else { return "?" }
    let code = d.enumCodeValue
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
    return String(decoding: bytes, as: UTF8.self)
}

@MainActor func aeSetListView(_ id: Int) throws {
    try finderAS("set current view of Finder window id \(id) to list view")
}

@MainActor func aeAllWindowIDs() -> [Int] {
    guard let d = try? finderAS("return id of every Finder window") else { return [] }
    if d.numberOfItems == 0 { return d.descriptorType == typeSInt32 ? [Int(d.int32Value)] : [] }
    return (1...d.numberOfItems).compactMap { d.atIndex($0).map { Int($0.int32Value) } }
}

@MainActor func aeFrontWindowID() -> Int? {
    (try? finderAS("return id of Finder window 1")).map { Int($0.int32Value) }
}

// MARK: - Finder + Visor

@MainActor final class FinderApp {
    let running: NSRunningApplication
    let pid: pid_t
    let ax: AXUIElement

    init() throws {
        guard let r = NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID).first else {
            throw SpikeError("Finder not running")
        }
        running = r
        pid = r.processIdentifier
        ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 1.0)
    }

    func windows() -> [AXUIElement] { axElements(ax, kAXWindowsAttribute) }
    func focusedWindow() -> AXUIElement? { axElement(ax, kAXFocusedWindowAttribute) }
    var isHidden: Bool { running.isHidden }
}

@MainActor final class Visor {
    let aeID: Int
    var ax: AXUIElement
    var cgID: CGWindowID
    var tabAEIDs: [Int] = []          // extra tabs created by this spike (closed on cleanup)
    var groupCGIDs: Set<CGWindowID>   // CG windows belonging to the Visor (incl. tab windows)

    init(aeID: Int, ax: AXUIElement, cgID: CGWindowID) {
        self.aeID = aeID
        self.ax = ax
        self.cgID = cgID
        groupCGIDs = [cgID]
    }
}

/// Windows (AE ids / AX elements) created by this process, closed on exit.
var createdAEIDs: [Int] = []
var finderHiddenByUs = false

@MainActor func cleanup() {
    if finderHiddenByUs, let f = try? FinderApp() {
        f.running.unhide()
        finderHiddenByUs = false
        pump(0.2)
    }
    for id in createdAEIDs.reversed() { aeClose(id) }
    createdAEIDs.removeAll()
}

@MainActor func installSignalCleanup() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    for sig in [SIGINT, SIGTERM] {
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler {
            MainActor.assumeIsolated {
                info("signal \(sig): cleaning up")
                cleanup()
                exit(130)
            }
        }
        src.resume()
        signalSources.append(src)
    }
}

var signalSources: [any DispatchSourceSignal] = []

/// Match a CG window of `pid` whose bounds equal `frame` ±2pt (D2 fallback when AE id ≠ CGWindowID).
func matchCGWindow(pid: pid_t, frame: CGRect, excluding: Set<CGWindowID> = []) -> CGWindowID? {
    cgList(.optionAll).first { $0.pid == pid && $0.layer == 0 && !excluding.contains($0.number)
        && approxEqual($0.bounds, frame) }?.number
}

/// D2 correlation: snapshot AXWindows, AE create → id, poll for a new AX element with the frame ±2pt.
@MainActor func createVisor(_ finder: FinderApp, frame: CGRect, label: String) throws -> (Visor, Double) {
    let before = finder.windows()
    let cgBefore = Set(cgList(.optionAll).filter { $0.pid == finder.pid }.map { $0.number })
    let t0 = nowMs()
    let id = try aeCreateWindow(frame: frame)
    createdAEIDs.append(id)
    var found: AXUIElement?
    var frameMatched = false
    _ = waitUntil(start: t0, timeoutMs: 1000) {
        let fresh = finder.windows().filter { w in !before.contains { CFEqual($0, w) } }
        if let m = fresh.first(where: { axFrame($0).map { approxEqual($0, frame) } ?? false }) {
            found = m; frameMatched = true; return true
        }
        if fresh.count == 1 { found = fresh[0] }
        return false
    }
    let createMs = nowMs() - t0
    guard let ax = found else { throw SpikeError("\(label): no new AX window appeared within 1 s (AE id \(id))") }
    let actual = axFrame(ax) ?? frame
    let cgID: CGWindowID
    if cgWindow(CGWindowID(id))?.pid == finder.pid {
        cgID = CGWindowID(id)
    } else if let m = matchCGWindow(pid: finder.pid, frame: actual, excluding: cgBefore) {
        cgID = m
    } else {
        throw SpikeError("\(label): no CGWindowList entry matches frame \(rectStr(actual))")
    }
    emit("create", [("label", label), ("aeID", "\(id)"), ("cgID", "\(cgID)"), ("aeIdIsCGWindowID", "\(cgID == CGWindowID(id))"),
                    ("frameMatched", "\(frameMatched)"), ("requested", rectStr(frame)), ("actual", rectStr(actual)),
                    ("createMs", f1(createMs)), ("pass", "\(createMs <= 1000 && frameMatched)")])
    return (Visor(aeID: id, ax: ax, cgID: cgID), createMs)
}

// MARK: - Visor geometry

@MainActor func computeVisorFrame(heightPct: Double) -> CGRect {
    let screens = NSScreen.screens
    guard let primary = screens.first else { return CGRect(x: 0, y: 0, width: 800, height: 400) }
    let primaryH = primary.frame.maxY
    let m = NSEvent.mouseLocation
    let s = screens.first { NSMouseInRect(m, $0.frame, false) }
        ?? screens.min { a, b in
            hypot(a.frame.midX - m.x, a.frame.midY - m.y) < hypot(b.frame.midX - m.x, b.frame.midY - m.y)
        }!
    let vf = s.visibleFrame
    let h = (vf.height * heightPct / 100).rounded()
    return CGRect(x: vf.minX, y: primaryH - vf.minY - h, width: vf.width, height: h)
}

enum ParkEdge: String { case br, bl, b, r, l }

/// P1 park origin outside the union of all displays for a window of `size`.
func parkPoint(size: CGSize, edge: ParkEdge, currentY: CGFloat) -> CGPoint {
    let u = displayRects().reduce(CGRect.null) { $0.union($1) }
    let gap: CGFloat = 100
    switch edge {
    case .br: return CGPoint(x: u.maxX + gap, y: u.maxY + gap)
    case .bl: return CGPoint(x: u.minX - size.width - gap, y: u.maxY + gap)
    case .b: return CGPoint(x: u.minX, y: u.maxY + gap)
    case .r: return CGPoint(x: u.maxX + gap, y: currentY)
    case .l: return CGPoint(x: u.minX - size.width - gap, y: currentY)
    }
}

// MARK: - Strategies

enum Strategy: String, CaseIterable { case p1, p2, p3 }

@MainActor final class Hider {
    let strategy: Strategy
    let finder: FinderApp
    let park: ParkEdge
    var lastPath = ""
    var p2Paths: [String: Int] = [:]

    init(_ s: Strategy, _ f: FinderApp, park: ParkEdge) { strategy = s; finder = f; self.park = park }

    /// P2 precondition: Visor is the only non-minimized Finder window on any Space.
    func visorIsSoleFinderWindow(_ v: Visor) -> (Bool, [CGWin]) {
        let visorBounds = cgWindow(v.cgID)?.bounds
        let minimized = finder.windows().filter { axBool($0, kAXMinimizedAttribute) == true }.compactMap { axFrame($0) }
        let others = cgList(.optionAll).filter { w in
            // Finder keeps small layer-0 helper windows (e.g. 1512x33 menu-bar strips, 64x64 drag images, observed
            // on macOS 27); only real browser windows (>= 200x150, alpha > 0) count as "other Finder windows".
            w.pid == finder.pid && w.layer == 0 && w.alpha > 0 && w.bounds.width >= 200 && w.bounds.height >= 150
                && !v.groupCGIDs.contains(w.number)
                && !(visorBounds.map { approxEqual($0, w.bounds) } ?? false)   // Visor's own tab windows
                && !minimized.contains { approxEqual($0, w.bounds) }
        }
        return (others.isEmpty, others)
    }

    func parkP1(_ v: Visor) {
        let size = axSize(v.ax) ?? CGSize(width: 800, height: 400)
        let y = axPosition(v.ax)?.y ?? 0
        axSetPosition(v.ax, parkPoint(size: size, edge: park, currentY: y))
    }

    func hide(_ v: Visor) {
        switch strategy {
        case .p1:
            parkP1(v); lastPath = "park"
        case .p2:
            let (sole, _) = visorIsSoleFinderWindow(v)
            if sole {
                finderHiddenByUs = true
                finder.running.hide()
                lastPath = "appHide"
            } else {
                parkP1(v); lastPath = "park(fallback)"
            }
            p2Paths[lastPath, default: 0] += 1
        case .p3:
            axSetBool(v.ax, kAXMinimizedAttribute, true); lastPath = "minimize"
        }
    }

    /// Show path normalizes every hidden state (plan "Show path"), then frame, raise, main, frontmost.
    func show(_ v: Visor, to frame: CGRect) {
        if axBool(v.ax, kAXMinimizedAttribute) == true { axSetBool(v.ax, kAXMinimizedAttribute, false) }
        if finder.running.isHidden { finder.running.unhide(); finderHiddenByUs = false }
        axSetPosition(v.ax, frame.origin)
        axSetSize(v.ax, frame.size)
        axSetPosition(v.ax, frame.origin)
        AXUIElementPerformAction(v.ax, kAXRaiseAction as CFString)
        axSetBool(v.ax, kAXMainAttribute, true)
        activateViaAX(pid: finder.pid)
    }

    func isShownAndKey(_ v: Visor) -> Bool {
        guard focusedAppPid() == finder.pid, let fw = finder.focusedWindow(), CFEqual(fw, v.ax) else { return false }
        return !cgHidden(v.cgID)
    }
}

// MARK: - Snapshots (H-3, H-4)

struct OtherWindowsSnapshot: Equatable {
    var ax: [String]                  // sorted "frame|minimized|title"
    var cgOnscreen: Set<CGWindowID>
    var cgBounds: [CGWindowID: String]
}

@MainActor func snapshotOthers(_ finder: FinderApp, _ v: Visor) -> OtherWindowsSnapshot {
    let vFrame = axFrame(v.ax)
    let ax = finder.windows().filter { w in
        !CFEqual(w, v.ax) && !(axFrame(w).flatMap { f in vFrame.map { approxEqual(f, $0) } } ?? false)
    }.map { w in
        "\(rectStr(axFrame(w)))|min=\(axBool(w, kAXMinimizedAttribute) ?? false)|\(axString(w, kAXTitleAttribute) ?? "")"
    }.sorted()
    let cg = cgList(.optionAll).filter { $0.pid == finder.pid && $0.layer == 0 && !v.groupCGIDs.contains($0.number) }
    return OtherWindowsSnapshot(ax: ax, cgOnscreen: Set(cg.filter { $0.onscreen }.map { $0.number }),
                                cgBounds: Dictionary(uniqueKeysWithValues: cg.map { ($0.number, rectStr($0.bounds)) }))
}

struct VisorStateSnapshot: Equatable {
    var targets: [String]
    var views: [String]
    var axTabCount: Int
}

func axTabCount(_ window: AXUIElement) -> Int {
    for child in axElements(window, kAXChildrenAttribute) where axString(child, kAXRoleAttribute) == kAXTabGroupRole {
        return axElements(child, kAXTabsAttribute).count > 0
            ? axElements(child, kAXTabsAttribute).count
            : axElements(child, kAXChildrenAttribute).filter { axString($0, kAXRoleAttribute) == kAXRadioButtonRole }.count
    }
    return 1
}

@MainActor func snapshotVisor(_ v: Visor) -> VisorStateSnapshot {
    let ids = [v.aeID] + v.tabAEIDs
    return VisorStateSnapshot(targets: ids.map { aeTarget($0) }, views: ids.map { aeView($0) }, axTabCount: axTabCount(v.ax))
}

/// Finds an enabled menu item with the given Cmd-only shortcut (locale independent).
func findMenuItem(_ app: AXUIElement, cmdChar: String) -> AXUIElement? {
    guard let bar = axElement(app, kAXMenuBarAttribute) else { return nil }
    for top in axElements(bar, kAXChildrenAttribute) {
        for menu in axElements(top, kAXChildrenAttribute) {
            for item in axElements(menu, kAXChildrenAttribute)
            where axString(item, kAXMenuItemCmdCharAttribute) == cmdChar
                && (axInt(item, kAXMenuItemCmdModifiersAttribute) ?? -1) == 0
                && axBool(item, kAXEnabledAttribute) != false {
                return item
            }
        }
    }
    return nil
}

/// H-4 setup: Visor gets 3 tabs (home, /Applications, /Library) and list view.
@MainActor func setupTabs(_ finder: FinderApp, _ v: Visor, hider: Hider, frame: CGRect) throws {
    hider.show(v, to: frame)
    pump(0.3)
    let aeBefore = aeAllWindowIDs().count
    let originalAX = v.ax
    let originalCG = v.cgID
    for path in ["/Applications", "/Library"] {
        guard let item = findMenuItem(finder.ax, cmdChar: "T") else { throw SpikeError("File > New Tab (⌘T) menu item not found") }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        pump(0.6)
        guard let front = aeFrontWindowID() else { throw SpikeError("no front Finder window after New Tab") }
        if front != v.aeID && !v.tabAEIDs.contains(front) { v.tabAEIDs.append(front); createdAEIDs.append(front) }
        try aeSetTarget(front, path)
        pump(0.3)
    }
    if let front = aeFrontWindowID() { try aeSetListView(front) }
    pump(0.5)
    // Tabs are separate NSWindows: the selected tab's window is the visible one. Re-resolve.
    if let fw = finder.focusedWindow() { v.ax = fw }
    if let f = axFrame(v.ax), let m = matchCGWindow(pid: finder.pid, frame: f, excluding: []) {
        let onscreenMatch = cgList(.optionOnScreenOnly).first { $0.pid == finder.pid && $0.layer == 0 && approxEqual($0.bounds, f) }
        v.cgID = onscreenMatch?.number ?? m
    }
    // All CG windows sharing the Visor frame belong to the tab group.
    if let f = axFrame(v.ax) {
        for w in cgList(.optionAll) where w.pid == finder.pid && approxEqual(w.bounds, f) { v.groupCGIDs.insert(w.number) }
    }
    emit("S2-tabs", [("aeWindowsBefore", "\(aeBefore)"), ("aeWindowsAfter", "\(aeAllWindowIDs().count)"),
                     ("tabsAreSeparateAEWindows", "\(!v.tabAEIDs.isEmpty)"), ("tabAEIDs", v.tabAEIDs.map(String.init).joined(separator: ",")),
                     ("axElementChanged", "\(!CFEqual(originalAX, v.ax))"), ("cgIDChanged", "\(originalCG != v.cgID)"),
                     ("visorCGIDs", v.groupCGIDs.map(String.init).sorted().joined(separator: ",")),
                     ("axTabCount", "\(axTabCount(v.ax))")])
}

/// H-3 setup: one normal + one minimized Finder window owned by this spike.
@MainActor func setupOtherWindows(_ finder: FinderApp) throws {
    guard let main = NSScreen.screens.first else { return }
    let primaryH = main.frame.maxY
    let vf = main.visibleFrame
    let top = primaryH - vf.maxY
    let normal = CGRect(x: vf.minX + 40, y: top + 40, width: 640, height: 360)
    _ = try createVisor(finder, frame: normal, label: "other-normal")
    let mini = CGRect(x: vf.minX + 120, y: top + 120, width: 600, height: 340)
    let (m, _) = try createVisor(finder, frame: mini, label: "other-minimized")
    axSetBool(m.ax, kAXMinimizedAttribute, true)
    pump(1.0)
}

// MARK: - run (automated checks)

struct StrategyResult {
    var h1: Double?, h2Area: Double = -1, h3 = false, h4 = false, h6 = false
    var show: Double?, hide: Double?
    var notes = ""
}

struct CycleStats {
    var h1: [Double] = [], showMs: [Double] = [], hideMs: [Double] = []
    var h1Timeouts = 0, showTimeouts = 0, keyFails = 0, worstDev = 0.0, worstArea = 0.0
}

/// `n` hide/show cycles; collects H-1, H-2 (geometry), H-6 and show/hide latency.
@MainActor func runCycles(_ n: Int, _ s: Strategy, _ hider: Hider, _ v: Visor, frame: CGRect, park: ParkEdge,
                          returnPid: pid_t?, phase: String) -> CycleStats {
    var st = CycleStats()
    for i in 0..<n {
        let t0 = nowMs()
        hider.hide(v)
        let hiddenAt = waitUntil(start: t0, timeoutMs: 3000) { cgHidden(v.cgID) }
        if let rp = returnPid { activateViaAX(pid: rp) }
        let returnedAt = waitUntil(start: t0, timeoutMs: 3000) { returnPid == nil || focusedAppPid() == returnPid }
        if let h = hiddenAt { st.h1.append(h) } else { st.h1Timeouts += 1 }
        if let h = hiddenAt, let r = returnedAt { st.hideMs.append(max(h, r)) }
        pump(s == .p3 ? 0.3 : 0.1)
        let area = cgVisibleArea(v.cgID)
        st.worstArea = max(st.worstArea, area)
        if i == 0 {
            emit("H-2-geometry", [("strategy", s.rawValue), ("phase", phase), ("path", hider.lastPath),
                                  ("axFrameWhileHidden", rectStr(axFrame(v.ax))), ("cgBounds", rectStr(cgWindow(v.cgID)?.bounds)),
                                  ("cgOnscreen", "\(cgWindow(v.cgID)?.onscreen ?? false)"), ("visibleArea", f1(area)),
                                  ("requestedPark", s == .p3 ? "-" : rectStr(CGRect(origin: parkPoint(size: frame.size, edge: park, currentY: frame.minY), size: frame.size)))])
        }
        let t1 = nowMs()
        hider.show(v, to: frame)
        if let ms = waitUntil(start: t1, timeoutMs: 3000, { hider.isShownAndKey(v) }) { st.showMs.append(ms) } else { st.showTimeouts += 1 }
        pump(0.05)
        if let f = axFrame(v.ax) { st.worstDev = max(st.worstDev, maxDeviation(f, frame)) } else { st.worstDev = .infinity }
        if !hider.isShownAndKey(v) { st.keyFails += 1 }
        pump(0.05)
    }
    return st
}

@MainActor func runStrategy(_ s: Strategy, cycles: Int, park: ParkEdge, heightPct: Double) throws -> StrategyResult {
    let finder = try FinderApp()
    let hider = Hider(s, finder, park: park)
    let returnPid = focusedAppPid().flatMap { $0 == finder.pid ? nil : $0 }
    info("strategy \(s.rawValue): return target pid = \(returnPid.map(String.init) ?? "none (Finder or unknown)")")
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "visor-\(s.rawValue)")
    pump(0.3)
    try setupTabs(finder, v, hider: hider, frame: frame)
    hider.show(v, to: frame)
    pump(0.5)
    // Phase A (latency, H-1): no helper windows, so P2 can take its app-hide path if the user has no other
    // Finder windows open.
    let a = runCycles(10, s, hider, v, frame: frame, park: park, returnPid: returnPid, phase: "A-latency")
    let pathA = hider.lastPath
    // Phase B (H-3/H-4/H-6): add one normal + one minimized Finder window owned by this spike.
    try setupOtherWindows(finder)
    hider.show(v, to: frame)
    pump(0.5)
    let othersBefore = snapshotOthers(finder, v)
    let visorBefore = snapshotVisor(v)
    info("others before: \(othersBefore.ax.count) AX windows, \(othersBefore.cgBounds.count) CG windows; visor: \(visorBefore)")
    let b = runCycles(cycles, s, hider, v, frame: frame, park: park, returnPid: returnPid, phase: "B-others")
    let (h1, showMs, hideMs, h1Timeouts, showTimeouts) = (a.h1, a.showMs, a.hideMs, a.h1Timeouts, a.showTimeouts)
    let keyFails = a.keyFails + b.keyFails
    let worstDev = max(a.worstDev, b.worstDev)
    let worstArea = max(a.worstArea, b.worstArea)
    info("phase A path=\(pathA); phase B path=\(hider.lastPath); phase B H-1 median=\(median(b.h1).map(f1) ?? "nil") ms")
    let othersAfter = snapshotOthers(finder, v)
    let visorAfter = snapshotVisor(v)

    var r = StrategyResult()
    r.h1 = median(Array(h1.prefix(10)))
    r.h2Area = worstArea
    r.h3 = othersBefore == othersAfter
    r.h4 = visorBefore == visorAfter
    r.h6 = worstDev <= 2 && keyFails == 0
    r.show = median(Array(showMs.prefix(10)))
    r.hide = median(Array(hideMs.prefix(10)))
    if s == .p2 { r.notes = "paths=" + hider.p2Paths.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",") }

    emit("H-1", [("strategy", s.rawValue), ("median10Ms", r.h1.map(f1) ?? "nil"), ("phaseBMedianMs", median(b.h1).map(f1) ?? "nil"),
                 ("maxMs", h1.max().map(f1) ?? "nil"), ("timeouts", "\(h1Timeouts)"),
                 ("pass", "\((r.h1 ?? .infinity) <= 100 && h1Timeouts == 0)"), ("pathA", pathA), ("pathB", hider.lastPath)])
    emit("H-2", [("strategy", s.rawValue), ("worstVisibleAreaPt2", f1(worstArea)), ("pass", "\(worstArea == 0)"),
                 ("note", "geometry-only;screenshot-check-is-manual")])
    emit("H-3", [("strategy", s.rawValue), ("cycles", "\(cycles)"), ("pass", "\(r.h3)"),
                 ("axBefore", "\(othersBefore.ax.count)"), ("axAfter", "\(othersAfter.ax.count)"),
                 ("onscreenBefore", "\(othersBefore.cgOnscreen.count)"), ("onscreenAfter", "\(othersAfter.cgOnscreen.count)")])
    if !r.h3 {
        info("H-3 diff AX before: \(othersBefore.ax)")
        info("H-3 diff AX after:  \(othersAfter.ax)")
    }
    emit("H-4", [("strategy", s.rawValue), ("pass", "\(r.h4)"), ("before", "\"\(visorBefore)\""), ("after", "\"\(visorAfter)\"")])
    emit("H-6", [("strategy", s.rawValue), ("worstFrameDevPt", f1(worstDev)), ("keyWindowFails", "\(keyFails)/\(cycles + 10)"),
                 ("pass", "\(r.h6)")])
    emit("latency", [("strategy", s.rawValue), ("showMedian10Ms", r.show.map(f1) ?? "nil"), ("showMaxMs", showMs.max().map(f1) ?? "nil"),
                     ("showTimeouts", "\(showTimeouts)"), ("hideMedian10Ms", r.hide.map(f1) ?? "nil"),
                     ("hideMaxMs", hideMs.max().map(f1) ?? "nil"),
                     ("showPass", "\((r.show ?? .infinity) <= 150)"), ("hidePass", "\((r.hide ?? .infinity) <= 150)"),
                     ("returnTarget", returnPid.map(String.init) ?? "none")])
    if s == .p2 { emit("P2-paths", [("paths", r.notes)]) }

    // leave the Visor hidden-free and close everything we created
    hider.show(v, to: frame)
    pump(0.2)
    cleanup()
    if let rp = returnPid { activateViaAX(pid: rp) }
    pump(0.5)
    return r
}

// MARK: - s2 / probe

@MainActor func runS2(heightPct: Double) throws {
    let finder = try FinderApp()
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "s2-visor")
    AXUIElementPerformAction(v.ax, kAXRaiseAction as CFString)
    pump(0.3)
    // A window of ours placed over the Visor must appear in optionOnScreenAboveWindow; the Visor itself must not.
    let over = CGRect(x: frame.minX + 50, y: frame.minY + 20, width: 500, height: 250)
    let (o, _) = try createVisor(finder, frame: over, label: "s2-over")
    AXUIElementPerformAction(o.ax, kAXRaiseAction as CFString)
    activateViaAX(pid: finder.pid)
    pump(0.5)
    let above = cgList(.optionOnScreenAboveWindow, v.cgID)
    let containsOver = above.contains { $0.number == o.cgID }
    let containsVisor = above.contains { $0.number == v.cgID }
    let below = cgList(.optionOnScreenBelowWindow, v.cgID)
    emit("S2", [("aeIdEqualsCGWindowID", "\(v.cgID == CGWindowID(v.aeID))"), ("visorAE", "\(v.aeID)"), ("visorCG", "\(v.cgID)"),
                ("aboveCount", "\(above.count)"), ("aboveContainsOverlay", "\(containsOver)"), ("aboveContainsVisor", "\(containsVisor)"),
                ("belowContainsOverlay", "\(below.contains { $0.number == o.cgID })"),
                ("pass", "\(containsOver && !containsVisor)")])
    cleanup()
}

@MainActor func runProbe(heightPct: Double) throws {
    let finder = try FinderApp()
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "probe-visor")
    pump(0.3)
    for edge in [ParkEdge.br, .bl, .b, .r, .l] {
        let req = parkPoint(size: frame.size, edge: edge, currentY: frame.minY)
        let err = axSetPosition(v.ax, req)
        pump(0.3)
        let actual = axFrame(v.ax)
        emit("P1-probe", [("edge", edge.rawValue), ("axError", "\(err.rawValue)"), ("requested", rectStr(CGRect(origin: req, size: frame.size))),
                          ("actualAX", rectStr(actual)), ("cgBounds", rectStr(cgWindow(v.cgID)?.bounds)),
                          ("cgOnscreen", "\(cgWindow(v.cgID)?.onscreen ?? false)"),
                          ("visibleAreaPt2", f1(cgVisibleArea(v.cgID))), ("zeroSliver", "\(cgVisibleArea(v.cgID) == 0)")])
        axSetPosition(v.ax, frame.origin)
        pump(0.2)
    }
    cleanup()
}

// MARK: - h9 (display changes while hidden)

@MainActor func runH9(_ s: Strategy, durationS: Double, park: ParkEdge, heightPct: Double) throws {
    _ = NSApplication.shared
    let finder = try FinderApp()
    let hider = Hider(s, finder, park: park)
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "h9-visor")
    pump(0.3)
    hider.hide(v)
    pump(0.5)
    info("H-9: Visor hidden (\(hider.lastPath)). Now unplug/re-plug the secondary display and/or rearrange displays in System Settings > Displays.")
    info("Watching for \(Int(durationS)) s (Ctrl-C to stop early).")
    var events = 0, failures = 0
    var pendingCheck: Double?
    let obs = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { _ in
        MainActor.assumeIsolated { pendingCheck = nowMs() }
    }
    let end = nowMs() + durationS * 1000
    var lastLog = 0.0
    while nowMs() < end {
        pump(0.05)
        if let t0 = pendingCheck {
            pendingCheck = nil
            events += 1
            if s != .p3 && hider.lastPath != "appHide" { hider.parkP1(v) }   // re-park against the new display union
            let ms = waitUntil(start: t0, timeoutMs: 2000) { cgHidden(v.cgID) }
            pump(max(0, 0.5 - (nowMs() - t0) / 1000))
            let area500 = cgVisibleArea(v.cgID)
            if area500 > 0 || ms == nil { failures += 1 }
            emit("H-9-event", [("strategy", s.rawValue), ("n", "\(events)"), ("hiddenAfterMs", ms.map(f1) ?? "timeout"),
                               ("visibleAreaAt500ms", f1(area500)), ("displays", "\"\(detectConfig().displays)\""),
                               ("axFrame", rectStr(axFrame(v.ax)))])
        }
        if nowMs() - lastLog > 5000 {
            lastLog = nowMs()
            let a = cgVisibleArea(v.cgID)
            if a > 0 { failures += 1 }
            info("H-9 tick: visibleArea=\(f1(a)) frame=\(rectStr(axFrame(v.ax)))")
        }
    }
    NotificationCenter.default.removeObserver(obs)
    emit("H-9", [("strategy", s.rawValue), ("screenEvents", "\(events)"), ("failures", "\(failures)"),
                 ("pass", events == 0 ? "untested(no-display-change)" : "\(failures == 0)")])
    hider.show(v, to: frame)
    pump(0.2)
    cleanup()
}

// MARK: - h10 (Finder relaunch while hidden) — the user runs `killall Finder`; this tool never does.

@MainActor func runH10(_ s: Strategy, park: ParkEdge, heightPct: Double) throws {
    let finder = try FinderApp()
    let hider = Hider(s, finder, park: park)
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "h10-visor")
    pump(0.3)
    hider.hide(v)
    pump(0.5)
    let oldPid = finder.pid
    let parkFrame = axFrame(v.ax)
    let target = aeTarget(v.aeID)
    info("H-10: Visor hidden (\(hider.lastPath)) at \(rectStr(parkFrame)), aeID=\(v.aeID), target=\(target).")
    info(">>> In ANOTHER terminal run:  killall Finder   (waiting up to 120 s for Finder to relaunch)")
    var newPid: pid_t?
    _ = waitUntil(start: nowMs(), timeoutMs: 120_000) {
        pump(0.2)
        if let r = NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID).first,
           r.processIdentifier != oldPid { newPid = r.processIdentifier; return true }
        return false
    }
    guard let np = newPid else {
        emit("H-10", [("strategy", s.rawValue), ("pass", "untested(Finder-not-relaunched)")])
        hider.show(v, to: frame); pump(0.2); cleanup(); return
    }
    info("Finder relaunched (pid \(oldPid) -> \(np)); waiting 4 s for window restoration")
    pump(4.0)
    finderHiddenByUs = false
    createdAEIDs.removeAll()   // old ids are invalid after relaunch (plan D2)
    let nf = try FinderApp()
    let idPersists = aeExists(v.aeID)
    let displays = displayRects()
    let wins = nf.windows()
    var candidates: [AXUIElement] = []
    for w in wins {
        let f = axFrame(w)
        let onscreen = f.map { intersectionArea($0, displays) > 0 } ?? false
        info("  restored window frame=\(rectStr(f)) minimized=\(axBool(w, kAXMinimizedAttribute) ?? false) onscreen=\(onscreen)")
        guard let f else { continue }
        let sizeOK = abs(f.width - frame.width) <= 4 && abs(f.height - frame.height) <= 4
        let atPark = parkFrame.map { abs($0.minX - f.minX) <= 4 && abs($0.minY - f.minY) <= 4 } ?? false
        let offAll = intersectionArea(f, displays) == 0
        let atVisible = approxEqual(f, frame, tol: 4)
        if sizeOK && (atPark || offAll || atVisible) { candidates.append(w) }
    }
    let adopted = candidates.count == 1 ? candidates[0] : nil
    let restored = adopted.flatMap { axFrame($0) }
    emit("H-10", [("strategy", s.rawValue), ("aeIdPersists", "\(idPersists)"), ("restoredFrame", rectStr(restored)),
                  ("restoredOnscreen", "\(restored.map { intersectionArea($0, displays) > 0 } ?? false)"),
                  ("reattachCandidates", "\(candidates.count)"), ("adopted", "\(adopted != nil)"),
                  ("pass", "\(adopted != nil)")])
    if let a = adopted {
        info("closing the adopted former Visor (created by this spike)")
        if let close = axElement(a, kAXCloseButtonAttribute) { AXUIElementPerformAction(close, kAXPressAction as CFString) }
    }
}

// MARK: - manual guided checks

@MainActor func prompt(_ text: String) -> String {
    print(">>> " + text)
    fflush(stdout)
    return readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
}

@MainActor func runManual(_ check: String, _ s: Strategy, park: ParkEdge, heightPct: Double) throws {
    let finder = try FinderApp()
    let hider = Hider(s, finder, park: park)
    let frame = computeVisorFrame(heightPct: heightPct)
    let (v, _) = try createVisor(finder, frame: frame, label: "manual-visor")
    pump(0.3)
    hider.show(v, to: frame)
    pump(0.3)
    hider.hide(v)
    pump(0.5)
    info("Visor hidden via \(hider.lastPath).")
    switch check.uppercased() {
    case "H-2":
        let a = prompt("H-2: take a screenshot of every display (Cmd-Shift-3) and inspect all edges/corners. Is ANY part of the Visor visible? [y/n]")
        emit("H-2-screenshot", [("strategy", s.rawValue), ("userSawSliver", a), ("geometryArea", f1(cgVisibleArea(v.cgID))),
                                ("pass", "\(a == "n" && cgVisibleArea(v.cgID) == 0)")])
    case "H-5":
        let steps = ["click Finder in the Dock", "click the desktop", "run `open -R ~/Documents` in another terminal (Reveal in Finder)",
                     "press Cmd-N in Finder (close that new window afterwards)", "switch Spaces (Ctrl-→ then Ctrl-←)"]
        var allPass = true
        for (i, step) in steps.enumerated() {
            _ = prompt("H-5.\(i + 1): \(step), then press Enter here")
            pump(0.5)
            let vis = !cgHidden(v.cgID)
            allPass = allPass && !vis
            emit("H-5", [("strategy", s.rawValue), ("step", "\(i + 1)"), ("action", "\"\(step)\""), ("visorVisible", "\(vis)"),
                         ("visibleArea", f1(cgVisibleArea(v.cgID))), ("pass", "\(!vis)")])
        }
        emit("H-5-summary", [("strategy", s.rawValue), ("pass", "\(allPass)")])
    case "H-7":
        _ = prompt("H-7: Cmd-Tab to Finder, press Cmd-` a few times, then type the letters abc (no other keys). Press Enter here")
        pump(0.3)
        let fw = finder.focusedWindow()
        let visorKey = fw.map { CFEqual($0, v.ax) } ?? false
        let a = prompt("H-7: did the type-select selection change in the (hidden) Visor or did you see it react? [y/n]")
        emit("H-7", [("strategy", s.rawValue), ("visorIsFinderKeyWindow", "\(visorKey)"), ("userSawLeak", a),
                     ("visorVisible", "\(!cgHidden(v.cgID))"), ("pass", "\(!visorKey && a == "n")")])
    case "H-8":
        let displays = displayRects()
        for (i, step) in ["press Cmd-N in Finder", "run `open -R ~/Documents` in another terminal (Reveal in Finder)"].enumerated() {
            let before = Set(cgList(.optionAll).filter { $0.pid == finder.pid }.map { $0.number })
            _ = prompt("H-8.\(i + 1): \(step), then press Enter here")
            pump(0.8)
            let fresh = cgList(.optionOnScreenOnly).filter { $0.pid == finder.pid && $0.layer == 0 && !before.contains($0.number) }
            let fully = fresh.allSatisfy { w in displays.contains { $0.contains(w.bounds) } }
            emit("H-8", [("strategy", s.rawValue), ("step", "\(i + 1)"), ("newWindows", "\(fresh.count)"),
                         ("frames", fresh.map { rectStr($0.bounds) }.joined(separator: ";")),
                         ("fullyOnScreen", "\(fully)"), ("visorVisible", "\(!cgHidden(v.cgID))"),
                         ("pass", "\(!fresh.isEmpty && fully && cgHidden(v.cgID))")])
        }
        info("Close the windows you opened in H-8 yourself (they are not owned by this spike).")
    default:
        throw SpikeError("unknown manual check \(check); use H-2, H-5, H-7 or H-8")
    }
    hider.show(v, to: frame)
    pump(0.2)
    cleanup()
}

// MARK: - main

@MainActor func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

@MainActor func mainEntry() -> Int32 {
    let args = CommandLine.arguments
    let cmd = args.count > 1 ? args[1] : "help"
    let park = ParkEdge(rawValue: arg("--park") ?? "br") ?? .br
    let heightPct = Double(arg("--height") ?? "40") ?? 40
    let strategies: [Strategy] = {
        let s = arg("--strategy") ?? "all"
        return s == "all" ? Strategy.allCases : [Strategy(rawValue: s) ?? .p1]
    }()
    installSignalCleanup()
    do {
        switch cmd {
        case "perm":
            let (ax, ae) = reportPermissions()
            return ax && ae == .granted ? 0 : 3
        case "config":
            reportConfig()
        case "s2":
            requirePermissions(); reportConfig()
            try runS2(heightPct: heightPct)
        case "probe":
            requirePermissions(); reportConfig()
            try runProbe(heightPct: heightPct)
        case "run":
            requirePermissions(); reportConfig()
            let cycles = Int(arg("--cycles") ?? "20") ?? 20
            var results: [(Strategy, StrategyResult)] = []
            for s in strategies {
                do { results.append((s, try runStrategy(s, cycles: cycles, park: park, heightPct: heightPct))) }
                catch { info("strategy \(s.rawValue) failed: \(error)"); cleanup() }
            }
            print("\nSUMMARY (config: \(detectConfig()))")
            print("strategy | H-1 med ms | H-2 area | H-3 | H-4 | H-6 | show med ms | hide med ms | notes")
            for (s, r) in results {
                print("\(s.rawValue) | \(r.h1.map(f1) ?? "-") | \(f1(r.h2Area)) | \(r.h3 ? "pass" : "FAIL") | \(r.h4 ? "pass" : "FAIL") | \(r.h6 ? "pass" : "FAIL") | \(r.show.map(f1) ?? "-") | \(r.hide.map(f1) ?? "-") | \(r.notes)")
            }
            print("Manual: H-2 screenshot, H-5, H-7, H-8 (HideSpike manual --check ...), H-9 (HideSpike h9), H-10 (HideSpike h10).")
        case "h9":
            requirePermissions(); reportConfig()
            try runH9(strategies[0], durationS: Double(arg("--duration") ?? "120") ?? 120, park: park, heightPct: heightPct)
        case "h10":
            requirePermissions(); reportConfig()
            try runH10(strategies[0], park: park, heightPct: heightPct)
        case "manual":
            requirePermissions(); reportConfig()
            try runManual(arg("--check") ?? "", strategies[0], park: park, heightPct: heightPct)
        default:
            print("usage: HideSpike perm|config|s2|probe|run|h9|h10|manual [--strategy p1|p2|p3|all] [--park br|bl|b|r|l] [--height 40] [--cycles 20] [--duration 120] [--check H-2|H-5|H-7|H-8]")
            return cmd == "help" ? 0 : 2
        }
    } catch {
        info("ERROR: \(error)")
        cleanup()
        return 1
    }
    cleanup()
    return 0
}

exit(MainActor.assumeIsolated { mainEntry() })
