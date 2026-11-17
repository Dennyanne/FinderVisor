import AppKit
import VisorCore

/// Screen geometry and mouse location in Cocoa coordinates.
@MainActor
protocol ScreenProvider {
    var screens: [ScreenGeometry] { get }
    /// Height of the primary screen (the one at the Cocoa origin), for Cocoa → AX conversion.
    var primaryScreenHeight: CGFloat { get }
    var mouseLocation: CGPoint { get }
}

struct LiveScreenProvider: ScreenProvider {
    var screens: [ScreenGeometry] {
        NSScreen.screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    var primaryScreenHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }

    var mouseLocation: CGPoint { NSEvent.mouseLocation }
}
