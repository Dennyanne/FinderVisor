import CoreGraphics
import Testing
@testable import VisorCore

private let visor = CGRect(x: 0, y: 660, width: 1512, height: 322)
private let other = CGRect(x: 100, y: 100, width: 800, height: 500)

private func window(_ id: UInt32, _ bounds: CGRect, onscreen: Bool) -> ListedWindow {
    ListedWindow(id: id, bounds: bounds, isOnscreen: onscreen)
}

/// Finder's measured layer-0 helper windows: four 1512x33 strips at 0,0 and one 64x64 window.
private let helpers = [
    window(90, CGRect(x: 0, y: 0, width: 1512, height: 33), onscreen: true),
    window(91, CGRect(x: 0, y: 0, width: 1512, height: 33), onscreen: true),
    window(92, CGRect(x: 0, y: 0, width: 1512, height: 33), onscreen: false),
    window(93, CGRect(x: 0, y: 0, width: 1512, height: 33), onscreen: false),
    window(94, CGRect(x: 700, y: 400, width: 64, height: 64), onscreen: true),
]

private func canHide(_ windows: [ListedWindow], visorIDs: Set<UInt32> = [1], minimized: [CGRect] = [],
                     returnsToFinder: Bool = false) -> Bool {
    AppHideDecision.canHideFinder(finderWindows: windows, visorIDs: visorIDs, minimizedFrames: minimized,
                                  returnsFocusToFinder: returnsToFinder)
}

@Suite struct AppHideDecisionTests {
    @Test func visorAloneAllowsAppHide() {
        #expect(canHide([window(1, visor, onscreen: true)]))
    }

    @Test func helperWindowsAreIgnored() {
        #expect(canHide([window(1, visor, onscreen: true)] + helpers))
    }

    @Test func visorTabsAreIgnored() {
        let windows = [window(1, visor, onscreen: false), window(2, visor, onscreen: false),
                       window(3, visor, onscreen: true)]
        #expect(canHide(windows, visorIDs: [1, 2, 3]))
    }

    @Test func onscreenOtherWindowForcesMinimize() {
        #expect(!canHide([window(1, visor, onscreen: true), window(5, other, onscreen: true)] + helpers))
    }

    @Test func minimizedOtherWindowAllowsAppHide() {
        #expect(canHide([window(1, visor, onscreen: true), window(5, other, onscreen: false)] + helpers,
                        minimized: [other]))
    }

    @Test func minimizedOtherTabGroupAllowsAppHide() {
        let windows = [window(1, visor, onscreen: true), window(5, other, onscreen: false),
                       window(6, other, onscreen: false)]
        #expect(canHide(windows, minimized: [CGRect(x: 101, y: 99, width: 801, height: 500)]))
    }

    @Test func otherSpaceWindowForcesMinimize() {
        #expect(!canHide([window(1, visor, onscreen: true), window(5, other, onscreen: false)]))
        let elsewhere = CGRect(x: 300, y: 200, width: 600, height: 400)
        #expect(!canHide([window(1, visor, onscreen: true), window(5, other, onscreen: false),
                          window(7, elsewhere, onscreen: false)], minimized: [other]))
    }

    @Test func nonVisorWindowAtVisorFrameCounts() {
        #expect(!canHide([window(1, visor, onscreen: true), window(8, visor, onscreen: false)]))
    }

    @Test func focusReturningToFinderForcesMinimize() {
        #expect(!canHide([window(1, visor, onscreen: true)], returnsToFinder: true))
    }
}
