import CoreGraphics
import Foundation
import VisorCore

/// CGWindowList access. Reads only bounds / layer / pid / number / alpha / on-screen (no Screen Recording needed;
/// `kCGWindowName` is never read).
protocol WindowListProvider: Sendable {
    /// Layer-0, non-transparent windows of `pid` across all Spaces, with their current-Space on-screen flag.
    func windows(ofPID pid: pid_t) -> [ListedWindow]
    /// On-screen windows above `windowID`, front to back.
    func windowsAbove(_ windowID: UInt32) -> [WindowInfo]
}

struct LiveWindowListProvider: WindowListProvider {
    func windows(ofPID pid: pid_t) -> [ListedWindow] {
        let onscreen = Set(entries(.optionOnScreenOnly).filter { $0.ownerPID == pid }.map(\.windowID))
        return entries(.optionAll)
            .filter { $0.ownerPID == pid && $0.layer == 0 && $0.alpha > 0 }
            .map { ListedWindow(id: $0.windowID, bounds: $0.bounds, isOnscreen: onscreen.contains($0.windowID)) }
    }

    func windowsAbove(_ windowID: UInt32) -> [WindowInfo] {
        entries(.optionOnScreenAboveWindow, relativeTo: windowID)
    }

    private func entries(_ option: CGWindowListOption, relativeTo windowID: CGWindowID = kCGNullWindowID) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(option, windowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
            return WindowInfo(
                windowID: UInt32(number),
                ownerPID: Int32(pid),
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
                bounds: bounds
            )
        }
    }
}
