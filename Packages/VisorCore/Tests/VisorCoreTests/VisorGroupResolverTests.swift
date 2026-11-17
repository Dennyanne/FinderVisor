import CoreGraphics
import Testing
@testable import VisorCore

private let visor = CGRect(x: 0, y: 508, width: 1440, height: 322)
private let other = CGRect(x: 100, y: 100, width: 800, height: 500)

private func window(_ id: UInt32, _ bounds: CGRect, onscreen: Bool) -> ListedWindow {
    ListedWindow(id: id, bounds: bounds, isOnscreen: onscreen)
}

private func resolve(_ members: Set<UInt32>, _ windows: [ListedWindow], last: CGRect? = visor, expand: Bool = true)
    -> VisorGroupResolution? {
    VisorGroupResolver.resolve(memberIDs: members, finderWindows: windows, lastFrame: last, allowExpansion: expand)
}

@Suite struct VisorGroupResolverTests {
    @Test func closedVisorResolvesToNil() {
        #expect(resolve([1], [window(2, other, onscreen: true)]) == nil)
        #expect(resolve([], [window(2, visor, onscreen: true)]) == nil)
    }

    @Test func singleVisibleWindow() {
        let result = resolve([1], [window(1, visor, onscreen: true), window(2, other, onscreen: true)])
        #expect(result == VisorGroupResolution(memberIDs: [1], anchorID: 1, activeID: 1, frame: visor))
    }

    @Test func minimizedVisorHasNoActiveTab() {
        let result = resolve([1], [window(1, visor, onscreen: false)], expand: false)
        #expect(result?.activeID == nil)
        #expect(result?.anchorID == 1)
    }

    @Test func newTabJoinsAndBecomesActive() {
        let result = resolve([1], [window(1, visor, onscreen: false), window(5, visor, onscreen: true)])
        #expect(result?.memberIDs == [1, 5])
        #expect(result?.activeID == 5)
    }

    @Test func switchingTabsFollowsTheSelectedTab() {
        let result = resolve([1, 5], [window(1, visor, onscreen: true), window(5, visor, onscreen: false)])
        #expect(result?.activeID == 1)
        #expect(result?.memberIDs == [1, 5])
    }

    @Test func closingTheActiveTabKeepsTheGroup() {
        let result = resolve([1, 5], [window(5, visor, onscreen: true)])
        #expect(result == VisorGroupResolution(memberIDs: [5], anchorID: 5, activeID: 5, frame: visor))
    }

    @Test func unrelatedWindowAtSameFrameIsNotAdoptedWhileMinimized() {
        let result = resolve([1], [window(1, visor, onscreen: false), window(9, visor, onscreen: true)], expand: false)
        #expect(result?.memberIDs == [1])
        #expect(result?.activeID == nil)
    }

    @Test func offscreenForeignWindowAtSameFrameNeverJoins() {
        // Minimized or on another Space, newer id: still not a tab of the Visor.
        let result = resolve([1], [window(1, visor, onscreen: true), window(9, visor, onscreen: false)])
        #expect(result?.memberIDs == [1])
        #expect(result?.activeID == 1)
    }

    @Test func olderWindowAtSameFrameNeverJoins() {
        let result = resolve([5], [window(5, visor, onscreen: false), window(2, visor, onscreen: true)])
        #expect(result?.memberIDs == [5])
        #expect(result?.activeID == nil)
    }

    @Test func twoOnscreenWindowsAtVisorFrameAreAmbiguous() {
        let result = resolve([1], [window(1, visor, onscreen: true), window(9, visor, onscreen: true)])
        #expect(result?.memberIDs == [1])
        #expect(result?.activeID == 1)
    }

    @Test func draggedOutTabLeavesTheGroup() {
        let result = resolve([1, 5], [window(1, visor, onscreen: true), window(5, other, onscreen: true)])
        #expect(result?.memberIDs == [1])
        #expect(result?.activeID == 1)
    }

    @Test func userMovedVisorIsStillTracked() {
        let moved = visor.offsetBy(dx: 0, dy: -200)
        let result = resolve([1, 5], [window(1, moved, onscreen: true), window(5, moved, onscreen: false)])
        #expect(result == VisorGroupResolution(memberIDs: [1, 5], anchorID: 1, activeID: 1, frame: moved))
    }

    @Test func noLastFrameFallsBackToLowestID() {
        let result = resolve([3, 8], [window(8, visor, onscreen: false), window(3, visor, onscreen: false)], last: nil)
        #expect(result?.anchorID == 3)
        #expect(result?.memberIDs == [3, 8])
    }
}
