// frame-dump — prints every Finder window's AX frame/minimized state and Finder's CGWindowList entries.
// Needs Accessibility for the AX part (CG part works without it). Never reads kCGWindowName (no Screen Recording).
// Usage: frame-dump [--all-pids]   (default: Finder only)

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func rectStr(_ r: CGRect?) -> String {
    guard let r else { return "-" }
    return "\(Int(r.minX.rounded())),\(Int(r.minY.rounded())) \(Int(r.width.rounded()))x\(Int(r.height.rounded()))"
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let pv = axCopy(el, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID(),
          let sv = axCopy(el, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

func displays() -> [CGRect] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    return ids.prefix(Int(n)).map { CGDisplayBounds($0) }
}

func visibleArea(_ r: CGRect) -> Int {
    Int(displays().reduce(0.0) { acc, d in
        let i = r.intersection(d)
        return acc + (i.isNull ? 0 : Double(i.width * i.height))
    })
}

let stamp = ISO8601DateFormatter().string(from: Date())
print("frame-dump \(stamp)  displays: " + displays().map(rectStr).joined(separator: " | "))

guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
    print("Finder is not running")
    exit(1)
}
let pid = finder.processIdentifier
print("Finder pid \(pid) hidden=\(finder.isHidden) active=\(finder.isActive) axTrusted=\(AXIsProcessTrusted())")

print("\n== AX windows (Finder) ==")
print(pad("#", 4) + pad("frame (top-left)", 26) + pad("minimized", 11) + pad("main", 6) + pad("onDisplayArea", 15) + "title")
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 1.0)
if let wins = axCopy(app, kAXWindowsAttribute) as? [AnyObject] {
    for (i, w) in wins.enumerated() where CFGetTypeID(w) == AXUIElementGetTypeID() {
        let el = w as! AXUIElement
        let f = axFrame(el)
        let mini = (axCopy(el, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false
        let main = (axCopy(el, kAXMainAttribute) as? NSNumber)?.boolValue ?? false
        let title = axCopy(el, kAXTitleAttribute) as? String ?? ""
        print(pad("\(i)", 4) + pad(rectStr(f), 26) + pad("\(mini)", 11) + pad("\(main)", 6)
              + pad(f.map { "\(visibleArea($0))" } ?? "-", 15) + title)
    }
} else {
    print("(unavailable — grant Accessibility to the host process)")
}

let allPids = CommandLine.arguments.contains("--all-pids")
print("\n== CGWindowList (optionAll\(allPids ? "" : ", Finder pid")) ==")
print(pad("number", 9) + pad("pid", 7) + pad("layer", 13) + pad("bounds (top-left)", 26) + pad("onscreen", 10) + pad("alpha", 7) + "onDisplayArea")
let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
for d in list {
    let wpid = d[kCGWindowOwnerPID as String] as? Int ?? -1
    guard allPids || wpid == Int(pid) else { continue }
    let num = d[kCGWindowNumber as String] as? Int ?? -1
    let layer = d[kCGWindowLayer as String] as? Int ?? 0
    let alpha = d[kCGWindowAlpha as String] as? Double ?? 0
    let onscreen = d[kCGWindowIsOnscreen as String] as? Bool ?? false
    let b = (d[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    print(pad("\(num)", 9) + pad("\(wpid)", 7) + pad("\(layer)", 13) + pad(rectStr(b), 26) + pad("\(onscreen)", 10)
          + pad(String(format: "%.2f", alpha), 7) + (b.map { "\(visibleArea($0))" } ?? "-"))
}
